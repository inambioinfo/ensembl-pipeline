package Bio::EnsEMBL::Pipeline::BatchSubmission::GridEngine;

BEGIN {
  require "Bio/EnsEMBL/Pipeline/pipeConf.pl";
}

use Bio::EnsEMBL::Pipeline::BatchSubmission;
use vars qw(@ISA);
use strict;

@ISA = qw(Bio::EnsEMBL::Pipeline::BatchSubmission);


sub new{
  my ($class, @args) = @_;
  my $self = $class->SUPER::new(@args);

  return $self;
 
}


##################
#accessor methods#
##################

sub qsub {
  my ($self,$qsub_line) = @_;

  if (defined($qsub_line)) {
    $self->{_qsub} = $qsub_line;
  }
  return $self->{_qsub};
}

##other accessor are in base class##

######################
#command line methods#
######################

sub construct_command_line{
  my($self, $command, $stdout, $stderr) = @_; 
  #print STDERR "creating the command line\n";
#command must be the first argument then if stdout or stderr aren't definhed the objects own can be used
  if(!$command){
    $self->throw("cannot create qsub if nothing to submit to it : $!\n");
  }
  my $qsub_line;
  $self->command($command);
  if($stdout){
    $qsub_line = "qsub -V -cwd -v FINAL_STDOUT=".$stdout;
  }else{
    $qsub_line = "qsub -V -cwd -v FINAL_STDOUT=".$self->stdout_file;
  }
  if($stderr){
    $qsub_line .= " -v FINAL_STDERR=".$stderr;
  }else{
    $qsub_line .= " -v FINAL_STDERR=".$self->stderr_file;
  }
  $qsub_line .= " -o /tmp -e /tmp";

# Depends on queues being made for each node with name node.q
  if($self->nodes){
    my $nodes = $self->nodes;
    # $nodes needs to be a space-delimited list
    $nodes =~ s/,/.q,/;
    $qsub_line .= " -q ".$nodes." ";
  }

  $qsub_line .= " -l ".$self->queue    if defined $self->queue;

  $qsub_line .= " -N ".$self->jobname  if defined $self->jobname;

  $qsub_line .= " ".$self->parameters." "  if defined $self->parameters;

  $qsub_line .= " -v PREEXEC=\"".$self->pre_exec."\"" if defined $self->pre_exec; 
  ## must ensure the prexec is in quotes ##
  $qsub_line .= " ge_wrapper.pl \"".$command . "\"";
  $self->qsub($qsub_line);
  #print "have command line\n";
}



sub open_command_line{
  my ($self)= @_;

  print STDERR $self->qsub."\n";
  print STDERR "opening command line\n";
  open(SUB, $self->qsub." 2>&1 |");
  my $geid;
  while(<SUB>){
    if (/your job (\d+)/) {
      $geid = $1;
    }
  }
  print STDERR "have opened ".$self->qsub."\n";
  print STDERR "geid ".$geid."\n";
  $self->id($geid);
  close(SUB);
}
