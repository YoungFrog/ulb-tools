#!/usr/bin/perl
use warnings;
use strict;
use WWW::Mechanize;
use HTML::TreeBuilder;
binmode STDOUT, ":utf8"; # spit utf8 to terminal
use utf8; # allow for utf8 inside the code.

my $name = shift;

die "Usage: $0 search-string\n" unless $name;
my $m = WWW::Mechanize->new();
my $tree = HTML::TreeBuilder->new;

# récupération du formulaire
$m->get('http://www.ulb.ac.be/commons/phonebook?mode=id-search');

die 'Échec de connexion : ' . $m->res->status_line()
  unless $m->success();

# remplissage et validation du formulaire
$m->submit_form(
                form_number => 1,
                fields => {
                           keyword => "$name"
                          }
               );


# connexion réussie ?
die 'Échec de validation du formulaire : ' . $m->res()->status_line()
  unless $m->success();

$tree->parse_content($m->content());

my @results = $tree->look_down("_tag","div","class","phonebookEntry");

exit 1 unless @results;

sub show_result {
  my $tree = $_;
  my $name = $tree->look_down("_tag","div","class",'phonebookName')->as_text();
  my $id = $tree->look_down("_tag","div","class",'phonebookId')->as_text();
  print "$id\000$name\n"
};

map (show_result, @results);
