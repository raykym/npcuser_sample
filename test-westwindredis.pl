#!/usr/bin/env perl

use strict;
use warnings;
use utf8;
use feature 'say';
use AnyEvent;
use EV;
use AnyEvent::Redis;
use DateTime;
use Encode qw(encode_utf8 decode_utf8);
use Mojo::JSON qw(encode_json decode_json from_json to_json);

$| = 1;

#一般コマンド用
my $redis = AnyEvent::Redis->new(
    host => '10.140.0.6',
    port => 6379,
    encoding => 'utf8',
    on_error => sub { warn @_ },
    on_cleanup => sub { warn "Connection closed: @_" },
);

#subscribe用
my $redisAE = AnyEvent::Redis->new(
    host => '10.140.0.6',
    port => 6379,
    encoding => 'utf8',
    on_error => sub { warn @_ },
    on_cleanup => sub { warn "Connection closed: @_" },
);

my $attackCH = 'ATTACKCHN';
my @chatArray = ( $attackCH ); # chatは受信させな

my $username = "DUMMY USERNAME";

sub Loging{
    my $logline = shift;
       $logline = encode_utf8($logline);
    my $dt = DateTime->now();
   #    $logline = decode_utf8($logline);
    say "$dt | $username: $logline";

    undef $logline;
    undef $dt;

    return;
}

    my $cv = AE::cv;
    my $t = AnyEvent->timer(
            after => 10,
            interval => 10,
               cb => sub {

        Loging("------------------------------LOOP START-----------------------------------");

     #redisで攻撃判定の受信
     # 以下redisイベント受信時の処理
     #redis receve subscribe
     my $AECV = $redisAE->subscribe($attackCH , sub {
                  my ($mess,$channel) = @_;
                      Loging("DEBUG: on channel: $channel | $mess");

                      if ( $channel ne $attackCH ) {
                                          undef $mess;
                                          return;
                         } # filter channel

                  ###    my $messobj = from_json($mess);

                      say $mess;

      });  # redis sub

        Loging("------------------------------LOOP END-------------------------------------");

    #   $cv->send;  # never end loop
       });  # AnyEvent CV
    $cv->recv;

