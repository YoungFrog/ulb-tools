#!/usr/bin/env perl

# Copyright (C) 2015 by Nicolas Richard

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.

use OpenOffice::OODoc;
use feature 'say';
use warnings;
use Getopt::Long;

# 0. Usage: perl $0 filename < fichier-avec-notes

# Où "fichier-avec-notes" a une note par ligne sous la forme
# "matricule note" (sans quotes)

sub usage {
  die<<EOF
Usage:
    perl $0 [--force] [--line PREMIERE-LIGNE] [--target COLONNE-NOTE ] [--column COLONNE-MATRICULE] filename < fichier-avec-notes
Où "fichier-avec-notes" est un fichier de la forme: une note par ligne
sous la forme:
matricule1 note1
matricule2 note2
EOF
}

my $line = 1;
my $col = "B"; #matricule
my $targetcol = "J"; #note
my $force = 0; # écraser l'existant ?

GetOptions ("line=i" => \$line, # i means integer
            "column=s" => \$col,          # s means string
            "target-column=s"  => \$targetcol,
            "force" => \$force)
or usage;

my $file = shift;
usage "No file given\n" unless $file;
usage "Non-existant file\n" unless -f $file;

# 1. Slurp stdin into a hash matricule => note
my %note;
while (<>) {
  my ($matricule, $note) = split;
  $note{$matricule} = $note
}

usage "No notes found on STDIN\n" unless %note;

# 2. loop over cell values in given column
my $doc = odfDocument(file => $file);
my $table = $doc->getTable(0);
# i.e. first table of document. See OpenOffice::OODoc::Text regarding
# the normalize argument. It can't be used however, probably the table
# is too large. We have:
# map { say } $doc->getTableSize($table);
# Returns 1048576 and 1024

my %seenmatricule; # remember matricules that were actually used
while (my $matricule = $doc->cellValue($table,"$col$line")) {
  if (defined $note{$matricule}) {
    $seenmatricule{$matricule}++;
    my $update = 0; # play safe : update explicitly.
    if (my $value = $doc->cellValue($table, "$targetcol$line")) {
      if (not ($note{$matricule} eq $value)) {
        if ($force) {
          $update = 1;
          warn "Cell $targetcol$line forcibly updated. Matricule/old value/new value: $matricule/$value/$note{$matricule}\n"
        } else {
          $update = 0;
          warn "Cell $targetcol$line skipped. Matricule/old value/new value: $matricule/$value/$note{$matricule}\n";
        }
      }
    } else {
      $update = 1;
    }
    if ($update) {
      $doc->cellValue($table, "$targetcol$line", $note{$matricule});
    }
  }
  $line++
}
map {
  my $seen = $seenmatricule{$_};
  if (defined $seen) {
    if ($seen > 1) {
      warn "Matricule vu plusieurs fois: $_\n";
    }
  } else {
     warn "Matricule non-utilisé: $_\n";
  }
} keys %note;

$doc->save;
