#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::UserAgent;
use Data::Dumper;

#Site1へのログインテスト

my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);


#my $tx = $ua->post('https://westwind.iobb.net/signinact' => form => { email => 'npcuser1@test.com', password => 'npcuser1_pass' });

#if (my $res = $tx->success){ say $res->body }
#   else {
#      my $err = $tx->error;
#      die "$err->{code} responce: $err->{message}" if $err->{code};
#      die "Connection error: $err->{message}";
#}

#my  $tx = $ua->get('https://westwind.iobb.net/walkworld/view');
#if (my $res = $tx->success){ say $res->body }
#   else {
#      my $err = $tx->error;
#      die "$err->{code} responce: $err->{message}" if $err->{code};
#      die "Connection error: $err->{message}";
#}

#my $lat = 35.677308 ;
#my $lng = 139.905534;
my $lat = 35.878619 ;
my $lng = 139.989712;

#my $keywd = '寺';
#my $keywd = '神社';
#my $keywd = 'コンビニ';
#my $keywd = '橋';
#my $keywd = '池';
my $keywd = '沼';

my $resjson = $ua->get("https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=5000&key=AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8&keyword=$keywd")->res->json;

my $resp = $resjson->{results};
my @respo = @$resp;

say "$_->{name} $_->{geometry}->{location}->{lat} $_->{geometry}->{location}->{lng} " for (@respo) ;

#say Dumper($resjson);

#   $tx = $ua->get("https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=1000&key=AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8&keyword=$keywd");

#if (my $res = $tx->success) { say $res->body }
#else {
#  my $err = $tx->error;
#  die "$err->{code} response: $err->{message}" if $err->{code};
#  die "Connection error: $err->{message}";
#}


