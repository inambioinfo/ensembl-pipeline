#!/usr/bin/env perl

=head1 NAME

align_by_component_identity_zfish.pl - create a whole genome alignment between two closely
related set of zebrafish assemblies for non-identical regions, step 2

=head1 SYNOPSIS

align_by_component_identity_zfish.pl [arguments]

Required arguments:

    --dbname, db_name=NAME              database name NAME
    --host, --dbhost, --db_host=HOST    database host HOST
    --port, --dbport, --db_port=PORT    database port PORT
    --user, --dbuser, --db_user=USER    database username USER
    --pass, --dbpass, --db_pass=PASS    database passwort PASS
    --from_assembly                     old assembly date
    --to_assembly                       new assembly date

Optional arguments:

    --from_cs_version                   coordinate system version, this option will overwrite from_assembly
    --conffile, --conf=FILE             read parameters from FILE
                                        (default: conf/Conversion.ini)
    --logfile, --log=FILE               log to FILE (default: *STDOUT)
    --logpath=PATH                      write logfile to PATH (default: .)
    --logappend, --log_append           append to logfile (default: truncate)

    -v, --verbose=0|1                   verbose logging (default: true)
    -i, --interactive=0|1               run script interactively (default: false)
    -n, --dry=0|1, --dry_run=0|1        don't write results to database (default: false)
    -h, --help, -?                      print help (this message)

=head1 DESCRIPTION

This script is part of a series of scripts to create a mapping between two
sets of zfish assemblies. It assembles the chromosome coordinate systems of
two different assemblies of a genome by creating a whole genome alignment
between the two.

The process handles major rearrangements or components moved from one chromosome
 to another.

See "Related files" below for an overview of the whole process.

This particular script creates a whole genome alignment between two closely
related sets of assemblies for non-identical regions. These regions are identified by
another script (align_by_component_identity_zfish.pl) and stored in a temporary
database table (tmp_align).

Alignments are calculated by this algorithm:

    1. fetch region from tmp_align
    2. write soft-masked sequences to temporary files
    3. align using lastz
    4. filter best hits (for query sequences, i.e. alternative regions) using
       axtBest
    5. parse lastz output to create blocks of exact matches only
    6. remove overlapping target (reference) alignments
    7. write alignments to assembly table

=head1 RELATED FILES

The whole process of creating a whole genome alignment between two sets of zfish assemblies
is done by a series of scripts. Please see scripts in

  ensembl-pipeline/scripts/Finished/assembly/

for a high-level description of this process, and POD in the individual scripts
for the details.

=head1 AUTHOR

Patrick Meidl <meidl@ebi.ac.uk>, Ensembl core API team

modified by Mustapha Larbaoui <ml6@sanger.ac.uk>

=head1 CONTACT

Please post comments/questions to Anacode
<anacode-people@sanger.ac.uk>

=cut

use strict;
use warnings;
no warnings 'uninitialized';

use FindBin qw($Bin);
use vars qw($SERVERROOT);
BEGIN {
    $SERVERROOT = "$Bin/../../../..";
    unshift(@INC, "$Bin");
}

use Getopt::Long;
use Pod::Usage;
use Bio::EnsEMBL::Utils::ConversionSupport;
use Bio::EnsEMBL::Utils::Exception qw(verbose throw warning);
use AssemblyMapper::BlastzAligner;


$| = 1;

my $support = new Bio::EnsEMBL::Utils::ConversionSupport($SERVERROOT);

$support->param('verbose', 1);
$support->param('interactive', 0);

# parse options
$support->parse_common_options(@_);
$support->parse_extra_options(
     'from_cs_version=s','from_assembly=s', 'to_assembly=s'
);
$support->allowed_params(
    $support->get_common_params,
    'from_cs_version=s','from_assembly', 'to_assembly'
);

if ($support->param('help') or $support->error) {
  warn $support->error if $support->error;
  pod2usage(1);
}

my $from_cs_version = $support->param('from_cs_version');
my $from_assembly = $support->param('from_assembly');
my $to_assembly = $support->param('to_assembly');

throw("Must set from_assembly or from_cs_version and to_assembly parameters!\n") unless(($from_assembly || $from_cs_version) && $to_assembly);

# get log filehandle and print heading and parameters to logfile
$support->init_log;

#####
# connect to database and get adaptors
#
my ($dba, $dbh, $sql, $sth);

# first set connection parameters for alternative db
# both databases have to be on the same host, so we don't need to configure
# them separately
for my $prm ( qw(host port user pass dbname) ) {
    $support->param("alt$prm", $support->param($prm)) unless ($support->param("alt$prm"));
}

# reference database
my $R_dba = $support->get_database('ensembl', '');
my $R_pipe_dba = &get_pipe_db($R_dba);
my $R_csa  = $R_dba->get_CoordSystemAdaptor;
my $R_dbh = $R_dba->dbc->db_handle;
my $R_sa = $R_dba->get_SliceAdaptor;

# database containing the alternative assembly
my $A_dba = $support->get_database('core', 'alt');
my $A_pipe_dba = &get_pipe_db($A_dba);
my $A_sa = $A_dba->get_SliceAdaptor;

# create BlastzAligner object
my $aligner = AssemblyMapper::BlastzAligner->new(-SUPPORT => $support);

# create tmpdir to store input and output
$aligner->create_tempdir();

# loop over non-aligned regions in tmp_align table
$support->log_stamped("Looping over non-aligned blocks...\n");

# list of all chromosome
my $chr_list  = $R_sa->fetch_all('chromosome'); # contains only default chromosome version

# add $from_cs_version chromosome version to chromosome list
if($from_cs_version) {
    foreach my $cs (@{$R_csa->fetch_all}) {
        push @$chr_list, @{$R_sa->fetch_all($cs->name,$cs->version)} if $cs->version eq $from_cs_version;
    }
}

# hash seq_region -> chromosome (e.g. chr23_20100514 -> 23)
my $sr_name_to_chr;
foreach my $chr_slice (@$chr_list) {
    my ($chr) = $chr_slice->seq_region_name =~ /chr(.*)_/;
    $chr = $chr_slice->seq_region_name unless $chr;
    $sr_name_to_chr->{$chr_slice->seq_region_name} = $chr;
}

# Reference chromsomes
my @from_chrs;
if($from_cs_version) {
    @from_chrs =
    sort { $sr_name_to_chr->{$a->seq_region_name} cmp $sr_name_to_chr->{$b->seq_region_name} }
    grep ( $_->coord_system->version eq $from_cs_version, @$chr_list );
} else {
    @from_chrs =
    sort { $sr_name_to_chr->{$a->seq_region_name} cmp $sr_name_to_chr->{$b->seq_region_name} }
    grep ( $_->seq_region_name =~ /$from_assembly/, @$chr_list );
}

# Alternative chromosomes
my @to_chrs =
  sort { $sr_name_to_chr->{$a->seq_region_name} cmp $sr_name_to_chr->{$b->seq_region_name} }
  grep ( $_->seq_region_name =~ /$to_assembly/, @$chr_list );


# throw up error if lists don't match in length
if ( !$from_cs_version && scalar(@from_chrs) != scalar(@to_chrs) ) {
    throw(   "Chromosome lists do not match by length:\n["
           . join( " ", map( $_->seq_region_name, @from_chrs ) ) . "]\n["
           . join( " ", map( $_->seq_region_name, @to_chrs ) )
           . "]\n" );
}


# Check that the chromosome names match
for my $i ( 0 .. scalar(@from_chrs) - 1 ) {
    my $R_sr_name = $from_chrs[$i]->seq_region_name;
    my $A_sr_name = $to_chrs[$i] ? $to_chrs[$i]->seq_region_name : "undef";
    my $R_chr = $sr_name_to_chr->{$R_sr_name};
    my $A_chr = $sr_name_to_chr->{$A_sr_name};

    throw(   "chromosome names don't match $R_chr != $A_chr\n["
           . join( " , ", map( $_->seq_region_name, @from_chrs ) ) . "]\n["
           . join( " , ", map( $_->seq_region_name, @to_chrs ) )
           . "]\n" )
      unless(($R_chr eq $A_chr) || $from_cs_version);
    $support->log_verbose("$R_sr_name   =>  $A_sr_name\n");
}

my @R_chr_list = map $_->seq_region_name , @from_chrs;
my @A_chr_list = map $_->seq_region_name , @to_chrs;

$sql = qq(SELECT * FROM tmp_align);
my @where = ();
if(@R_chr_list) {
  my $chr_string = join("', '", @R_chr_list);
  push @where, "ref_seq_region_name IN ('$chr_string')";
}
if(@A_chr_list) {
  my $altchr_string = join("', '", @A_chr_list);
  push @where, "alt_seq_region_name IN ('$altchr_string')";
}
if(scalar(@where)) {
    $sql .= ' WHERE '.join(' AND ', @where);
}

$sql .= ' ORDER BY (alt_end - alt_start) ASC';

$sth = $R_dbh->prepare($sql);
$sth->execute;

BLOCK: while (my $row = $sth->fetchrow_hashref) {

  my $id = $row->{'tmp_align_id'};
  $aligner->id($id);
  $aligner->seq_region_name($row->{'ref_seq_region_name'});

  $support->log_stamped("Block with tmp_align_id = $id\n", 1);

  # write sequences to file
  my $A_basename = "alt_seq.$id";
  my $R_basename = "ref_seq.$id";

  $support->log("Writing sequences to fasta...\n", 2);

  # This is needed otherwise will get a sequence of N's for the ref slice
  ($R_pipe_dba ? $R_pipe_dba : $R_dba)->get_AssemblyMapperAdaptor()->delete_cache();

   my $R_slice;
  if ($R_pipe_dba) {
    eval {
        $R_slice = $R_pipe_dba->get_SliceAdaptor->fetch_by_region(
          'chromosome',
          $row->{'ref_seq_region_name'},
          $row->{'ref_start'},
          $row->{'ref_end'},
          1,
          $from_cs_version ? $from_cs_version : undef
        );
    };
  }
  $R_slice = $R_dba->get_SliceAdaptor->fetch_by_region(
      'chromosome',
      $row->{'ref_seq_region_name'},
      $row->{'ref_start'},
      $row->{'ref_end'},
      1,
      $from_cs_version ? $from_cs_version : undef
   ) unless $R_slice;


  $aligner->write_sequence(
      $R_slice,
      undef,
      $R_basename
  );

  # This is needed otherwise will get a sequence of N's for the alt slice
  ($A_pipe_dba ? $A_pipe_dba : $A_dba)->get_AssemblyMapperAdaptor()->delete_cache();


  my $A_slice;
  if($A_pipe_dba){
      eval {
    $A_slice = $A_pipe_dba->get_SliceAdaptor->fetch_by_region(
      'chromosome',
      $row->{'alt_seq_region_name'},
      $row->{'alt_start'},
      $row->{'alt_end'},
      1,
    );
    };
  }
  $A_slice = $A_dba->get_SliceAdaptor->fetch_by_region(
      'chromosome',
      $row->{'alt_seq_region_name'},
      $row->{'alt_start'},
      $row->{'alt_end'},
      1,
   ) unless $A_slice;

   $aligner->write_sequence(
      $A_slice,
      undef,
      $A_basename
  );

  $support->log("Done.\n", 2);

  # skip unmasked ref/alt sequences longer than 1.1MB
  # This will avoid everlasting alignment...
   $support->log("Checking sequences...\n", 2);
   if($aligner->bad_sequences($A_basename, $R_basename)){
        $support->log("Skip block $id (not soft-masked and too long)...\n", 2);
        next BLOCK;
   }

  # align using lastz
  $support->log("Running lastz...\n", 2);
  $aligner->run_lastz($A_basename, $R_basename);
  $support->log("Done.\n", 2);


  # find best alignment with axtBest
  $support->log("Finding best alignment with axtBest...\n", 2);
  $aligner->find_best_alignment;
  $support->log("Done.\n", 2);

  # parse lastz output, and convert relative alignment coordinates to
  # chromosomal coords
  $support->log("Parsing lastz output...\n", 2);

  $aligner->parse_lastz_output;

  $aligner->adjust_coords(
      $row->{'alt_start'},
      $row->{'alt_end'},
      { $id => [ $row->{'ref_start'}, $row->{'ref_end'} ] }
  );

  $support->log("Done.\n", 2);

  # log alignment stats
  $aligner->log_block_stats(2);

  $support->log_stamped("Done with block $id.\n", 1);

} # while ($row = fetchrow...)

$support->log_stamped("Done.\n");

# write alignments to assembly table
$aligner->write_assembly($R_dba, \@R_chr_list, \@A_chr_list);

# overall stats
$aligner->log_overall_stats;

# remind to drop tmp_align
$support->log("\nDon't forget to drop the tmp_align table when all is done!\n\n");

# finish logfile
$support->finish_log;

sub get_pipe_db {
    my ($dba) = @_;
    my $metakey = 'pipeline_db_head';
    my ($opt_str) = @{ $dba->get_MetaContainer()->list_value_by_key($metakey) };

    return undef unless $opt_str;

    my %anycase_options = (
        eval $opt_str,
    );
    if ($@) {
        throw("Error evaluating '$opt_str' : $@");
    }
    my %uppercased_options = ();
    while( my ($k,$v) = each %anycase_options) {
        $uppercased_options{uc($k)} = $v;
    }

    return Bio::EnsEMBL::DBSQL::DBAdaptor->new(%uppercased_options);
}


