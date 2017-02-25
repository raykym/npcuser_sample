#!/usr/bin/env perl

# login load test module.......

#
# npcuser_f.pl [email] [emailpass] {lat} {lng} {mode}
# email passwordは必須

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use DateTime;
use Math::Trig qw(great_circle_distance rad2deg deg2rad pi);
use Clone qw(clone);

$| = 1;

# npcuser用モジュール

if ( $#ARGV < 1 ) {
    say "npcuser_f.pl [email] [emailpass] {lat} {lng} {mode}";
    exit;
}


my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

my $email = "$ARGV[0]";
my $emailpass = "$ARGV[1]";
say "$email";
say "$emailpass";

################# loop start
#ループ処理 
#    Mojo::IOLoop->recurring(
#                     60 => sub {
#
# Login認証
my $tx = $ua->post('https://westwind.iobb.net/signinact' => form => { email => "$email", password => "$emailpass" });

if (my $res = $tx->success){ say $res->body }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}

say "signinact page on";
say "";

my $username = "";
my $userid = "";

# 認証を通ればページはパスできる事を確認
  $tx = $ua->get('https://westwind.iobb.net/walkworld/view');
if (my $res = $tx->success){ 

    # username useridを取得する
    my @respage = split(/;/,$res->body);
    say "PAGE COUNT: $#respage";
    foreach  my $line (@respage){
        if ( $line =~ /_username_/ ){
            my @l = split(/"/,$line);
            $username = $l[1];
            say "$username";
            }
        if ( $line =~ /_uid_/ ){
            my @l = split(/"/,$line);
            $userid = $l[1];
            say "$userid";
            }
        } # foreach

    say "WebSocket Connect $username";

   }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}


# websocketでの位置情報送受信
  $ua->websocket('wss://westwind.iobb.net/walkworld' => sub {
    my ($ua,$tx) = @_;

    $tx->on(finish => sub {
       my ($tx, $code, $reason) = @_;
       say "WebSocket closed with status $code. $username";
       $tx->finish;
       exit;
    });

    $tx->finish if ($tx->is_websocket);

   }); # ua websocket

#
#  }); #ループ

#   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;
############ loop end

