#
#
# Cared for by EnsEMBL  <ensembl-dev@ebi.ac.uk>
#
# Copyright GRL & EBI
#
# You may distribute this module under the same terms as perl itself
#
# POD documentation - main docs before the code

=pod 

=head1 NAME

Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM

=head1 SYNOPSIS

    my $obj = Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM->new(
					     -dbobj     => $db,
					     -input_id  => $id
                                             );
    $obj->fetch_input
    $obj->run

    my @newfeatures = $obj->output;


=head1 DESCRIPTION

runs HalfwiseHMM runnable and converts it output into genes which can be stored in an ensembl database

=head1 CONTACT

lec@sanger.ac.uk

=head1 APPENDIX

The rest of the documentation details each of the object methods. 
Internal methods are usually preceded with a _

=cut

# Let the code begin...

package Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM;

use Bio::EnsEMBL::Pipeline::RunnableDB;
use Bio::Root::RootI;

use vars qw(@ISA);
use strict;

use Bio::EnsEMBL::Pipeline::Runnable::HalfwiseHMM;


@ISA = qw(Bio::EnsEMBL::Pipeline::RunnableDB);

=head2  new

    Arg      : all those inherited from RunnableDB
    Function : Make a new HalfwiseHMM object defining the above variables
    Exception: thrown if no input id is provided, this is found in RunnableDB
    Caller   : 
    Example  : $runnable = Bio::EnsEMBL::Pipeline::RunnableDB::HalfwiseHMM new->(-DBOBJ => $db
										 -INPUT_ID => $id
										 -ANALYSIS => $analysis);

=cut


sub new {
    my ($new,@args) = @_;
    my $self = $new->SUPER::new(@args);    
           
    # dbobj, input_id, seqfetcher, and analysis objects are all set in
    # in superclass constructor (RunnableDB.pm)

    $self->{'_fplist'} = []; #create key to an array of feature pairs
    return $self;
}


=head2  fetch_input

    Arg      : none
    Function : fetches the repeatmasked sequence and the swall features for the contig being run on and creates the HalfwiseHMM Runnable
    Exception: throws if no input_id has been provided
    Caller   : 
    Example  : 

=cut

sub fetch_input {
  my( $self) = @_;
  #print "running fetch input\n";  
  my @fps;
  my %ests;
  my @estseqs;
  $self->throw("No input id") unless defined($self->input_id);
  
  my $contigid  = $self->input_id;
  my $contig    = $self->dbobj->get_Contig($contigid);
  #print "got contig\n";
  my $genseq   = $contig->primary_seq;
  #print "got dnaseq\n";
  my @features = $contig->get_all_SimilarityFeatures_above_score("swall", 1);
  #print $features[0]."\n";
  #print "got data\n";
  
  foreach my $f (@features) {
    if ($f->isa("Bio::EnsEMBL::FeaturePair") && 
	defined($f->hseqname)) {
      push(@fps, $f);
    }
  }
  #print "got".scalar(@fps)." feature pairs\n";

  my $runnable  = Bio::EnsEMBL::Pipeline::Runnable::HalfwiseHMM->new('-genomic'     => $genseq, 
									    '-features' => \@fps,
								    );
  #print "created HalfwiseHMM Runnable\n";  
  $self->runnable($runnable);
  #print "finshed fetching input\n";
}    
      
  
    
    
=head2  runnable

    Arg      : a Bio::EnsEMBL::Pipeline::RunnableI
    Function : Gets/sets the runnable 
    Exception: throws if argument passed isn't a runnable
    Caller   : 
    Example  :'

=cut    
    



sub runnable {
    my ($self,$arg) = @_;

    if (defined($arg)) {
	$self->throw("[$arg] is not a Bio::EnsEMBL::Pipeline::RunnableI") unless $arg->isa("Bio::EnsEMBL::Pipeline::RunnableI");
	
	$self->{_runnable} = $arg;
    }

    return $self->{_runnable};
}


=head2  run

    Arg      : none
    Function : runs the runnable and runs _convert_output(); 
    Exception: thows if no runnable is defined
    Caller   : 
    Example  :

=cut

sub run {
    my ($self) = @_;
    #print "running halfwisehmm\n";
    my $runnable = $self->runnable;
    $runnable || $self->throw("Can't run - no runnable object");
    #print "halfwiseDB\n";
    $runnable->run;
    #print "halfwiseDB\n";
    $self->_convert_output();
    
}
 

=head2  output

    Arg      : none
    Function : returns the output from the halfwisehmm runnable
    Exception: none
    Caller   : 
    Example  :

=cut


#sub output {
#    my ($self) = @_;
#    my @out = $self->runnable->output();
#    return @out;
#}
 

=head2  write_output


    Arg      : none
    Function : writes the converted output to the database as genes
    Exception: none
    Caller   : 
    Example  :

=cut

sub write_output {

  my($self) = @_;
  #$self->_convert_output();
  my @genes    = $self->output();
  
  my $db       = $self->dbobj();


  my $gene_adaptor= $self->dbobj->get_GeneAdaptor;

  GENE: foreach my $gene (@genes) {	
    # do a per gene eval...
    eval {
      #print "gene = ".$gene->type()."\n";
      $gene_adaptor->store($gene);
    }; 
    if( $@ ) {
      print STDERR "UNABLE TO WRITE GENE\n\n$@\n\nSkipping this gene\n";
    }
    
  }
   return 1;
}


=head2  _convert_output

    Arg      : none
    Function : takes the features from the halfwise runnable and runs _make_genes to convert them into Bio::EnsEMBL::Genes with appropriately attached exons and supporting evidence
    Exception: thows if there are no analysis types
    Caller   : 
    Example  :

=cut


sub _convert_output {
  my ($self) = @_;
  #print "converting genes to features\n";
  my @genes;
  my $genetype = 'Halfwise';
  my $anaAdaptor = $self->dbobj->get_AnalysisAdaptor;
  my @analyses = $anaAdaptor->fetch_by_logic_name($genetype);
  my $analysis;
  if(scalar(@analyses) > 1){
    $self->throw("panic! > 1 analysis for $genetype\n");
  }
  elsif(scalar(@analyses) == 1){
    $analysis = $analyses[0];
  }else{
    # make a new analysis object
    $analysis = new Bio::EnsEMBL::Analysis
      (
       -program         => 'genewise',
       -program_version => 1,
       -gff_source      => 'HalfwiseHMM',
       -gff_feature     => 'gene',
       -logic_name      => 'Halfwise',
       -module          => 'HalfwiseHMM',
      );
  }
   # make an array of genes for each runnable
    my $runnable = $self->runnable();
    my @out = $runnable->output;
    #print "HalfwiseDB\n";
    #"converting ".scalar(@out)." features to genes\n";
    my @g = $self->_make_genes($genetype, $analysis, \@out);
    push(@genes, @g);
  
 #print STDOUT "genes = @genes\n";

    
  if (!defined($self->{_output})) {
    $self->{_output} = [];
  }
  
  push(@{$self->{_output}},@genes);
}

=head2  _make_genes

    Arg      : runnable being run and analysis object being used
    Function : converts the seqfeatures outputed by the runnable and actually converts them into Bio::EnsEMBL::Genes
    Exception: none
    Caller   : 
    Example  :

=cut



=head2 make_genes

  Title   :   make_genes
  Usage   :   $self->make_genes
  Function:   makes Bio::EnsEMBL::Genes out of the output from runnables
  Returns :   array of Bio::EnsEMBL::Gene  
  Args    :   $genetype: string
              $analysis_obj: Bio::EnsEMBL::Analysis
              $results: reference to an array of FeaturePairs

=cut

sub _make_genes {
  my ($self, $genetype, $analysis_obj, $results) = @_;
  my $contig = $self->dbobj->get_Contig($self->input_id);
  my @tmpf   = @$results;
  my @genes;
#  print "genetype = ".$genetype."\n";
  foreach my $tmpf (@tmpf) {
    my $gene       = new Bio::EnsEMBL::Gene;
    my $transcript = $self->_make_transcript($tmpf, $contig, $genetype, $analysis_obj);

    $gene->type($genetype);
    $gene->analysis($analysis_obj);
    $gene->add_Transcript($transcript);

    push (@genes, $gene)
  }

  return @genes;

}

=head2 _make_transcript

 Title   : make_transcript
 Usage   : $self->make_transcript($gene, $contig, $genetype)
 Function: makes a Bio::EnsEMBL::Transcript from a SeqFeature representing a gene, 
           with sub_SeqFeatures representing exons.
 Example :
 Returns : Bio::EnsEMBL::Transcript with Bio::EnsEMBL:Exons(with supporting feature 
           data), and a Bio::EnsEMBL::translation
 Args    : $gene: Bio::EnsEMBL::SeqFeatureI, $contig: Bio::EnsEMBL::DB::ContigI,
  $genetype: string, $analysis_obj: Bio::EnsEMBL::Analysis


=cut

sub _make_transcript{
  my ($self, $gene, $contig, $genetype, $analysis_obj) = @_;
  $genetype = 'unspecified' unless defined ($genetype);

  unless ($gene->isa ("Bio::EnsEMBL::SeqFeatureI"))
    {print "$gene must be Bio::EnsEMBL::SeqFeatureI\n";}
  unless ($contig->isa ("Bio::EnsEMBL::DB::ContigI"))
    {print "$contig must be Bio::EnsEMBL::DB::ContigI\n";}

  my $transcript   = new Bio::EnsEMBL::Transcript;
  my $translation  = new Bio::EnsEMBL::Translation;    
  $transcript->translation($translation);

  my $excount = 1;
  my @exons;
    
  foreach my $exon_pred ($gene->sub_SeqFeature) {
    # make an exon
    my $exon = new Bio::EnsEMBL::Exon;
    
    $exon->contig_id($contig->internal_id);
    $exon->start($exon_pred->start);
    $exon->end  ($exon_pred->end);
    $exon->strand($exon_pred->strand);
    
    $exon->phase($exon_pred->phase);
    $exon->attach_seq($contig);
    
    # sort out supporting evidence for this exon prediction
    foreach my $subf($exon_pred->sub_SeqFeature){
      $subf->feature1->seqname($contig->internal_id);
      $subf->feature1->source_tag($genetype);
      $subf->feature1->primary_tag('similarity');
      $subf->feature1->score(100);
      $subf->feature1->analysis($analysis_obj);
        
      $subf->feature2->source_tag($genetype);
      $subf->feature2->primary_tag('similarity');
      $subf->feature2->score(100);
      $subf->feature2->analysis($analysis_obj);
      
      $exon->add_Supporting_Feature($subf);
    }
    
    push(@exons,$exon);
    
    $excount++;
  }
  
  if ($#exons < 0) {
   # printSTDERR "Odd.  No exons found\n";
  } 
  else {
    
    #print STDERR "num exons: " . scalar(@exons) . "\n";

    if ($exons[0]->strand == -1) {
      @exons = sort {$b->start <=> $a->start} @exons;
    } else {
      @exons = sort {$a->start <=> $b->start} @exons;
    }
    
    foreach my $exon (@exons) {
      $transcript->add_Exon($exon);
    }
    
    $translation->start_exon($exons[0]);
    $translation->end_exon  ($exons[$#exons]);
    
    if ($exons[0]->phase == 0) {
      $translation->start(1);
    } elsif ($exons[0]->phase == 1) {
      $translation->start(3);
    } elsif ($exons[0]->phase == 2) {
      $translation->start(2);
    }
    
    $translation->end  ($exons[$#exons]->end - $exons[$#exons]->start + 1);
  }
  
  return $transcript;
}



=head2 output

 Title   : output
 Usage   :
 Function: get/set for output array
 Example :
 Returns : array of Bio::EnsEMBL::Gene
 Args    :


=cut

sub output{
   my ($self,@genes) = @_;
  
   if (!defined($self->{'_output'})) {
     $self->{'_output'} = [];
   }
    
   if(defined @genes){
     push(@{$self->{'_output'}},@genes);
   }
   
   return @{$self->{'_output'}};
}

1;
