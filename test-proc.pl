#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';
use Proc::ProcessTable;

  my $proceslist = new Proc::ProcessTable;

  foreach my $p (@{$proceslist->table}){
      my $line = $p->cmndline;
      if ( $line =~ /npcuser/ ){
          my @pname = split(/ /,$line);
          say "$pname[2]";
          }
      }
