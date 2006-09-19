# You may distribute this module under the same terms as perl itself

# POD documentation - main docs before the code

=head1 NAME

Bio::EnsEMBL::Pipeline::Config::GeneBuild::Sequences - imports global variables used by EnsEMBL gene building

=head1 SYNOPSIS
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Sequences;
    use Bio::EnsEMBL::Pipeline::Config::GeneBuild::Sequences qw(  );

=head1 DESCRIPTION

Sequences is a pure ripoff of humConf written by James Gilbert.

humConf is based upon ideas from the standard perl Env environment
module.

It imports and sets a number of standard global variables into the
calling package, which are used in many scripts in the human sequence
analysis system.  The variables are first decalared using "use vars",
so that it can be used when "use strict" is in use in the calling
script.  Without arguments all the standard variables are set, and
with a list, only those variables whose names are provided are set.
The module will die if a variable which doesn\'t appear in its
C<%Sequences> hash is asked to be set.

The variables can also be references to arrays or hashes.

Edit C<%Sequences> to add or alter variables.

All the variables are in capitals, so that they resemble environment
variables.

=head1 CONTACT

=cut


package Bio::EnsEMBL::Pipeline::Config::GeneBuild::Sequences;

use strict;
use LowCoverageGeneBuildConf;
use vars qw( %Sequences );

# Hash containing config info
%Sequences = (

	      # path to species specific protein index
	      GB_PROTEIN_INDEX => $LC_PROT_INDEX, 

	      # type of SeqFetcher to use
	      # eg 'Bio::EnsEMBL::Pipeline::SeqFetcher::OBDAIndexSeqFetcher',
	      GB_PROTEIN_SEQFETCHER =>  'Bio::EnsEMBL::Pipeline::SeqFetcher::OBDAIndexSeqFetcher', 

	      # path to cDNA index
	      GB_CDNA_INDEX    => '/ecs4/work3/ba1/armadillo1/seqdata/arma_cdnas',

	      GB_CDNA_SEQFETCHER => 'Bio::EnsEMBL::Pipeline::SeqFetcher::OBDAIndexSeqFetcher'
	      
	   );

sub import {
  my ($callpack) = caller(0); # Name of the calling package
  my $pack = shift; # Need to move package off @_
  
  # Get list of variables supplied, or else
  # all of Sequences:
  my @vars = @_ ? @_ : keys( %Sequences );
  return unless @vars;
  
  # Predeclare global variables in calling package
  eval "package $callpack; use vars qw("
    . join(' ', map { '$'.$_ } @vars) . ")";
    die $@ if $@;


    foreach (@vars) {
	if ( defined $Sequences{ $_ } ) {
            no strict 'refs';
	    # Exporter does a similar job to the following
	    # statement, but for function names, not
	    # scalar variables:
	    *{"${callpack}::$_"} = \$Sequences{ $_ };
	} else {
	    die "Error: Sequences: $_ not known\n";
	}
    }
}

1;