#!/usr/bin/perl -w
use strict;
use List::MoreUtils qw(firstidx);
use WWW::Mechanize;
binmode STDOUT, ":utf8"; # spit utf8 to terminal
use utf8; # allow for utf8 inside the code.
use IO::Prompter;
# use HTML::TreeBuilder;
# use LWP::Debug;
# use Devel::Peek;
use HTML::FormatText::WithLinks;

my $username = "nrichard";
my $password = prompt 'Enter your password: ', -echo=>'';
my $destfile="mathematiques.xml";
my $file = "/home/youngfrog/ownCloud/ulb/site/tmp/$destfile";

my $url="http://www.ulb.ac.be/sitemanager/admin";
my $urlselectproject = "http://www.ulb.ac.be/sitemanager/admin?mode=selectProjectDone&directory=:ulb-facultes:facultes:sciences&project=facultes:sciences:mathematiques&";
my $urlupload = "http://www.ulb.ac.be/sitemanager/admin?_mode=uploadFile&type=xml-source&source=main&name=$destfile";
my $urlgenerate = "http://www.ulb.ac.be/sitemanager/admin?mode=generateProject";

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

print "Selection du projet...\n"
$m-> get("$urlselectproject");
die 'Échec de connexion (sélection du projet) : ' . $m->res->status_line()
  unless $m->success();

# Il faut trouver le bon formulaire. Même en ne gardant que ceux avec
# _file_data et _paneid il en reste deux, donc il faut trouver le bon
# à la main! On a besoin de son index pour pouvoir le sélectionner.
my $formnum = 1 + firstidx { my $filedata;
                             my $editmain;
                             map {
                               if ($_->name  eq '_file_data') {
                                 $filedata = 1;
                               }
                               if (($_->name eq '_paneid') and ($_->value eq 'paneEditmain_edit')) {
                                 $editmain = 1;
                               }
                             } $_->inputs;
                             $filedata && $editmain;
                           } $m-> forms;


# my @fields_for_uploading_file = ("_file_data" );

print "Soumission du fichier: $file...\n";

my $form = $m->form_number($formnum);
$form->action("$urlupload");
# $form->accept_charset ($m->response()->content_charset);

my $input = $form->find_input("_file_data");
$input->value($file);
# $input->filename("$destfile");
# $input->headers("Content-Type" => "text/xml");

## debug the request :
# $m->add_handler("request_send", sub { my $req = shift; print $req->as_string() ; return });


# this does not work : $m->submit()
# (the visible reason is that the _submit inputfield (= submit field)
# is not transmitted in that case.)
$m->click("_submit");
print HTML::FormatText::WithLinks->new()->parse($m->content);

print "Re-génération du projet en prévisualisation...\n"
$m->get("$urlgenerate");
print HTML::FormatText::WithLinks->new()->parse($m->content);

1;

# Local Variables:
# coding: utf-8-unix
# End:
