#!/usr/bin/perl -w
use strict;
use WWW::Mechanize;
binmode STDOUT, ":utf8"; # spit utf8 to terminal
use utf8; # allow for utf8 inside the code.
use IO::Prompter;
# use HTML::TreeBuilder;
# use LWP::Debug;
# use Devel::Peek;
use File::Copy;


my $username = "nrichard";
my $password = prompt 'Enter password: ', -echo=>'';
my $destfile="mathematiques.xml";
my $file ="/home/youngfrog/ownCloud/ulb/site/$destfile";
my $tmpfile = "/home/youngfrog/ownCloud/ulb/site/$destfile.new";

my $url="http://www.ulb.ac.be/sitemanager/admin";
my $urlselectproject = "http://www.ulb.ac.be/sitemanager/admin?mode=selectProjectDone&directory=:ulb-facultes:facultes:sciences&project=facultes:sciences:mathematiques&";
my $urldownload = "http://www.ulb.ac.be/sitemanager/admin?_mode=downloadFileToDisk&type=xml-source&source=main&name=$destfile";

my $m = WWW::Mechanize->new();

print "Connexion...\n";
# récupération du formulaire d'identification
$m->get("$url");

die 'Échec de connexion : ' . $m->res->status_line()
  unless $m->success();

print "Identification...\n";

# remplissage et soumission du formulaire d'identification
$m->submit_form(
                form_number => 1,
                fields => {
                           _username => "$username",
                           _password => "$password"
                          }
               );

die 'Échec lors de la soumission du formulaire : ' . $m->res()->status_line()
  unless $m->success();

print "Selection du projet...\n";
$m-> get("$urlselectproject");
die 'Échec de connexion (sélection du projet) : ' . $m->res->status_line()
  unless $m->success();

print "Téléchargement du fichier vers: $tmpfile...\n";

$m->get("$urldownload");

die 'Échec du téléchargement : ' . $m->res->status_line()
  unless $m->success();

$m->save_content("$tmpfile", binary => 1);

print "Différences:\n";

my $samep = (system("diff", "-u", "$file", "$tmpfile") == 0);

if ($samep) {
  unlink $tmpfile;
  print "Aucune différence trouvée. Fichier temporaire effacé: $tmpfile.\n"
} elsif (prompt(-yes,-prompt => "Écraser l'ancien fichier ?")) {
  move($tmpfile,$file);
} else {
  print "Fichier temporaire laissé sur place: $tmpfile.\n"
}



1;

# Local Variables:
# coding: utf-8-unix
# End:
