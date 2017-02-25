#!/usr/bin/env perl

#
# npcuser_f.pl [email] [emailpass] {lat} {lng} {mode}
# email passwordは必須

# simple chatroomへの書き込み機能を追加

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use DateTime;
use Math::Trig qw(great_circle_distance rad2deg deg2rad pi);
#use Clone qw(clone);

use Mojo::IOLoop::Delay;

$| = 1;

$ENV{MOJO_USERAGENT_DEBUG}=1;

# searchnpc用モジュール
# google placeからキーワード検索して、移動場所を決定する

if ( $#ARGV < 1 ) {
    say "searchnpc.pl [email] [emailpass] {lat} {lng} {mode}";
    exit;
}


my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

my $email = "$ARGV[0]";
my $emailpass = "$ARGV[1]";
say "$email";
say "$emailpass";


# Login認証
my $tx = $ua->post('https://westwind.iobb.net/signinact' => form => { email => "$email", password => "$emailpass" });

if (my $res = $tx->success){ say $res->body }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}

my $username = "";
my $userid = "";

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

# 初期値
my $lat = 35.677543 + rand(0.001) - (0.001/2);
    if (defined($ARGV[2])){
        $lat = $ARGV[2] + 0;  # 数値化の+0
       }
my $lng = 139.9055707 + rand(0.001) - (0.001/2);
    if (defined($ARGV[3])){
        $lng = $ARGV[3] + 0;
        }
my $s_lat = $lat;
my $s_lng = $lng;
my $runmode = "random";
    if (defined($ARGV[4])){
        $runmode = $ARGV[4];
       } 


my $icon_url = ""; # 暫定
my $timerecord;
my $point_spn = 0.002;
my $direct_reng = 90;
my $rundirect = int(rand(360));
my $apikey = "AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8";
my $radi = 1000; #検索レンジ

my $npcuser_stat = { 
         "geometry" => {
                     "type" => "Point",
                     "coordinates" => [ $lng , $lat ]
                     },
          "loc" => { "lat" => $lat,
                     "lng" => $lng 
                   },
          "name" => $username,
          "userid" => $userid,
          "status" => $runmode,
          "rundirect" => $rundirect,
          "time" => $timerecord,
          "icon_url" => $icon_url,
          "target" => "",                     # uid
          "place" => { "lat" => "",           # 検索結果
                       "lng" => "",
                       "name" => "",
                     },
           };

# アイコン変更処理
iconchg($npcuser_stat->{status});

# $runmodeが重複しているから注意
sub iconchg {
    my $runmode = shift;
if ( $runmode eq "random"){
     $npcuser_stat->{icon_url} = "/img/ghost2_32px.png";
    } elsif ( $runmode eq "search"){ 
     $npcuser_stat->{icon_url} = "/img/ghost4_32px.png";
    } elsif ( $runmode eq "runaway" ){
     $npcuser_stat->{icon_url} = "/img/ghost3_32px.png";
    } elsif ( $runmode eq "round" ){
     $npcuser_stat->{icon_url} = "/img/ghost1_32px.png";
    } elsif ( $runmode eq "STAY"){ 
     $npcuser_stat->{icon_url} = "/img/ghost2_32px.png";
    }
    
}

my $pointlist;
#my $targetlist;   # searchnpcでは利用しない
my $targets = [];
my $oncerun = "true";

my @keyword = ( "コンビニ",
                "銀行",
                "役所",
                "スーパー",
                "駅",
                "図書館",
                "レストラン",
                "神社",
                "寺",
              );

   if ($oncerun) {
      # 1回のみ送信 起動直後のマーカー表示用
      $ua->websocket('wss://westwind.iobb.net/walkworld' => sub {
          my ($ua,$tx) = @_;
              iconchg($npcuser_stat->{status});
              sendjson($tx);
              $oncerun = "false";   
        }); 
      }

#ループ処理 websocketも再接続される 60secで更新に変更 追いかけっこしない想定なら60秒も有り
    Mojo::IOLoop->recurring(
                     60 => sub {
                           my $loop = shift;

# websocketでの位置情報送受信
  $ua->websocket('wss://westwind.iobb.net/walkworld' => sub {
    my ($ua,$tx) = @_;

    $tx->on(json => sub {
        my ($tx,$hash) = @_;

            # 終了判定
            if ( defined $hash->{to} ){
                if ( $hash->{to} eq $userid ) {

                    my $delay = Mojo::IOLoop::Delay->new;
                       $delay->steps(

                       sub {
                        my $delay = shift;
                            Mojo::IOLoop->timer(5 => $delay->begin);
                            say "$username 祓われた。。。";

                            my $hitparam = { to => $hash->{to}, execute => $hash->{execute}, hitname => $username };
                            $tx->send({ json => $hitparam });

                            my $chatmsg = "そして$username は祓われた！";

                            writeChat($chatmsg);
                       },
                       sub {
                        my ($delay,@param) = @_;

                        exit;

                       })->wait;

               } else { return; } # 自分のUIDでなければパスする。
             }

         say "webSocket responce! $email : $npcuser_stat->{status}";
            $pointlist = $hash->{pointlist};
         #   $targetlist = clone($pointlist);
        }); #on json
    
    $tx->on(finish => sub {
       my ($tx, $code, $reason) = @_;
       say "WebSocket closed with status $code. $username";
       $tx->finish;
    #   exit;
    });

             # テスト用　位置保持
             if ( $npcuser_stat->{status} eq "STAY") {
                 iconchg($npcuser_stat->{status});
                 sendjson($tx);
                 return;
                }

             my $rundirect = $npcuser_stat->{rundirect};

             # ランダム移動処理
             if ( $npcuser_stat->{status} eq "random" ){

                my $runway_dir = 1;

                if ($rundirect < 90) { $runway_dir = 1; }
                if (( 90 < $rundirect)&&( $rundirect < 180)) { $runway_dir = 2; }
                if (( 180 < $rundirect)&&( $rundirect < 270 )) { $runway_dir = 3; }
                if (( 270 < $rundirect)&&( $rundirect < 360 )) { $runway_dir = 4; }


                if ($runway_dir == 1) {
                          $lat = $lat + rand($point_spn);
                          $lng = $lng + rand($point_spn);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          if ($rundirect < 0 ) {
                             $rundirect = $rundirect + 360;
                             }
                          }
                if ($runway_dir == 2) {
                          $lat = $lat - rand($point_spn);
                          $lng = $lng + rand($point_spn);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          }
                if ($runway_dir == 3) {
                          $lat = $lat - rand($point_spn);
                          $lng = $lng - rand($point_spn);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          }
                if ($runway_dir == 4) {
                          $lat = $lat + rand($point_spn);
                          $lng = $lng - rand($point_spn);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          if ($rundirect > 360 ) {
                             $rundirect = $rundirect - 360;
                             }
                          }

                # モード変更チェック 
                if (int(rand(10)) > 7) {
                        $npcuser_stat->{status} = "search";
                        say "Mode change Search!";
                        sendjson($tx);
                        return;
                   }

             } # if stat random

             # 検索モード
             if ( $npcuser_stat->{status} eq "search" ){

               if ($npcuser_stat->{place}->{name} eq "") {

                   my $selnum = int(rand($#keyword));
                   my $keywd = $keyword[$selnum];
                   say "DEBUG: $selnum : $keywd";

                  # target select
                   my $resjson = $ua->get("https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radi&key=$apikey&keyword=$keywd")->res->json;

                    undef $selnum;
                    undef $keywd;

                    if ( $resjson->{status} eq "ZERO_RESULTS" ) {
                               say "Null responce!";       

                               $npcuser_stat->{status} = "random";
                               $npcuser_stat->{place}->{name} = "";
                               $npcuser_stat->{place}->{lat} = "";
                               $npcuser_stat->{place}->{lng} = "";
                               say "Mode change random!";
                               sendjson($tx);
                               return;
                       }

                    my $list = $resjson->{results};
                    my @pointlist = @$list;
                    my $slice = int(rand($#pointlist));
                    say "slice: $slice";
                    my $deb = to_json($pointlist[$slice]);
                    say "DEBUG: slice: $deb";

                    $npcuser_stat->{place}->{lat} = $pointlist[$slice]->{geometry}->{location}->{lat} + 0;
                    $npcuser_stat->{place}->{lng} = $pointlist[$slice]->{geometry}->{location}->{lng} + 0;
                    $npcuser_stat->{place}->{name} = $pointlist[$slice]->{name};


                    my $chatmsg = "今から$npcuser_stat->{place}->{name}へ行くよ！";
                    writeChat($chatmsg);

                    say "DEBUG: Place: $npcuser_stat->{place}->{name} $npcuser_stat->{place}->{lat} $npcuser_stat->{place}->{lng}"; 

                } # if nameが空ならば

                # move
                my $runway_dir = 1;

                   $rundirect = geoDirect($npcuser_stat->{loc}->{lat}, $npcuser_stat->{loc}->{lng}, $npcuser_stat->{place}->{lat}, $npcuser_stat->{place}->{lng});
                say "DEBUG: rundirect: $rundirect ";

                if ($rundirect < 90) { $runway_dir = 1; }
                if (( 90 < $rundirect)&&( $rundirect < 180)) { $runway_dir = 2; }
                if (( 180 < $rundirect)&&( $rundirect < 270 )) { $runway_dir = 3; }
                if (( 270 < $rundirect)&&( $rundirect < 360 )) { $runway_dir = 4; }

                say "DEBUG: runway_dir: $runway_dir ";

                if ($runway_dir == 1) {
                          $lat = $lat + rand($point_spn);
                          $lng = $lng + rand($point_spn);
                          }
                if ($runway_dir == 2) {
                          $lat = $lat - rand($point_spn);
                          $lng = $lng + rand($point_spn);
                          }
                if ($runway_dir == 3) {
                          $lat = $lat - rand($point_spn);
                          $lng = $lng - rand($point_spn);
                          }
                if ($runway_dir == 4) {
                          $lat = $lat + rand($point_spn);
                          $lng = $lng - rand($point_spn);
                          }

                # radianに変換
                sub NESW { deg2rad($_[0]), deg2rad($_[1]) }
                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($npcuser_stat->{place}->{lng}, $npcuser_stat->{place}->{lat});
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                say "DEBUG: dist: $t_dist";

                if ( $t_dist > 50 ) {
                     $point_spn = 0.002;
                   } elsif ($t_dist < 50 ) {
                     $point_spn = 0.0002; 
                   }

               if ( $t_dist < 5 ) {
                   $point_spn = 0.002;  #元に戻す
                   $npcuser_stat->{status} = "random";
                   $npcuser_stat->{place}->{name} = "";
                   $npcuser_stat->{place}->{lat} = "";
                   $npcuser_stat->{place}->{lng} = "";
                   say "Mode change random!";
                   sendjson($tx);
                   return;
               }

             } # search

# 2点間の距離を算出 (度) 
sub geoDirect {
    my ($lat1, $lng1, $lat2, $lng2) = @_;

    my $Y = cos ($lng2 * pi / 180) * sin($lat2 * pi / 180 - $lat1 * pi / 180);

    my $X = cos ($lng1 * pi / 180) * sin($lng2 * pi / 180 ) - sin($lng1 * pi /180) * cos($lng2 * pi / 180 ) * cos($lat2 * pi / 180 - $lat1 * pi / 180);

    my $dirE0 = 180 * atan2($Y,$X) / pi;
    if ($dirE0 < 0 ) {
        $dirE0 = $dirE0 + 360;
       }
    my $dirN0 = ($dirE0 + 90) % 360;

    return $dirN0;
    }

# 送信処理 npcuser_statを時刻チェックして送信する。
sub sendjson {
    my $tx = shift;
                 $timerecord = DateTime->now()->epoch();
                 $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
                 $npcuser_stat->{time} = $timerecord;

                 $tx->send( { json => $npcuser_stat } );
                 return;
}

              # 送信処理 random search 共通
              $timerecord = DateTime->now()->epoch();
              $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
              $npcuser_stat->{time} = $timerecord;

              $npcuser_stat->{geometry}->{coordinates}= [ $lng, $lat ];
              $npcuser_stat->{loc}->{lat} = $lat;
              $npcuser_stat->{loc}->{lng} = $lng; 
              $npcuser_stat->{rundirect} = $rundirect;

              iconchg($npcuser_stat->{status});

              say "DEBUG: lat: $lat ( $npcuser_stat->{loc}->{lat} )  lng: $lng ( $npcuser_stat->{loc}->{lng} )";

              $tx->send( { json => $npcuser_stat } );
              return;
          }); #ループ

          $tx->finish if ($tx->is_websocket);

   }); # ua websocket

   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

# simple chatroomへの接続処理
# modeチェンジのタイミングでログと同様にchatへコメントを書き込む
# ws関連の変数重複に注意
# ブラウザが過去にchatroomに接続していれば、通るはず。。。
sub writeChat {
    my $msg = shift;

    # websocketでの位置情報送受信
       $ua->websocket('wss://westwind.iobb.net/menu/chatroom/echodb' => sub {
        my ($ua,$txchat) = @_;

           $txchat->send($msg);

        $txchat->on(finish => sub {
           my ($tx, $code, $reason) = @_;
           say "Chat WebSocket closed with status $code. $username";
           $txchat->finish;
           });  # on finish

      }) unless ($tx->is_websocket); # websocket
}


