#!/usr/bin/env perl

#
# searchnpc_n.pl [email] [emailpass] {lat} {lng} {mode}
# email passwordは必須
# walkchatを追加した版
# 緯度経度の通過処理追加
# Logingを追加

# simple chatroomへの書き込み機能を追加

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use DateTime;
use Math::Trig qw(great_circle_distance rad2deg deg2rad pi);
use Clone qw(clone);

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

# 表示用ログフォーマット
sub Loging{
    my $logline = shift;
    my $dt = DateTime->now();

    say "$dt | $email : $logline";
    return;
}


# Login認証
my $tx = $ua->post('https://www.backbone.site/signinact' => form => { email => "$email", password => "$emailpass" });

if (my $res = $tx->success){ say $res->body }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}

my $username = "";
my $userid = "";

  $tx = $ua->get('https://www.backbone.site/walkworld/view');

if (my $res = $tx->success){ 

    # username useridを取得する
    my @respage = split(/;/,$res->body);
    Loging("PAGE COUNT: $#respage");
    foreach  my $line (@respage){
        if ( $line =~ /_username_/ ){
            my @l = split(/"/,$line);
            $username = $l[1];
            Loging("$username");
            }
        if ( $line =~ /_uid_/ ){
            my @l = split(/"/,$line);
            $userid = $l[1];
            Loging("$userid");
            }
        } # foreach

    Loging("WebSocket Connect $username");

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

my $lifecount = 60480; #1week /10sec count

my $icon_url = ""; # 暫定
my $timerecord;
my $point_spn = 0.0002;
my $direct_reng = 90;
my $rundirect = int(rand(360));
my $apikey = "AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8";
my $radi = 3000; #検索レンジ

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
          "category" => "NPC",
           };

my $txtmsg = "";
my $chatobj = {
            "chat" => $txtmsg,
            "geometry" => {
                     "type" => "Point",
                     "coordinates" => [ $lng , $lat ]
                     },
            "loc" => { "lat" => $lat,
                       "lng" => $lng
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
    } elsif ( $runmode eq "chase" ){
     $npcuser_stat->{icon_url} = "/img/ghost4_32px.png";
    }
    
}

sub spnchange {
       my $t_dist = shift;
          if ( $t_dist > 50 ) {
               $point_spn = 0.0002;
               Loging("point_spn: $point_spn");
             } else {
               $point_spn = 0.0001;
               Loging("point_spn: $point_spn");
             }
}

my $pointlist;
my $targetlist; # chaseモード追加で利用 
my $targets = [];
my $oncerun = "true";

# 東経西経北緯南偉の範囲判定　１：東経北緯　２：西経北緯　３：東経南偉　４：西経南偉
# 方位判定は北極基準で360度の判定。結果、同じ方角でも境目を超えると値の増減が変わる為の判定
sub geoarea {
    my ($lat,$lng) = @_;

    my $resp = 1;

    if (( 0 < $lat) and ($lat < 180) and (0 < $lng) and ( $lng < 90)) { $resp = 1; }
    if ((-180 < $lat ) and ( $lat < 0 ) and ( 0 < $lng) and ( $lng < 90 )) { $resp = 2;}
    if (( 0 < $lat ) and ( $lat < 180 ) and ( -90 < $lng ) and ( $lng < 0 )) { $resp = 3;}
    if ((-180 < $lat ) and ( $lat < 0 ) and ( -90 < $lng ) and ( $lng < 0 )) { $resp = 4;}

    return $resp ;
}

# -90 < $lat < 90
sub overArealat {
    my ($lat) = shift;
        # 南半球は超えても南半球
        if ( $lat < -90 ) {
            my $dif = abs($lat) - 90;
            $lat = -90 + $dif;
            $rundirect = $rundirect - 180; #グローバル変数に方向性を変更
            return $lat;
         }
        # 北半球は超えても北半球
        if ( 90 < $lat ) {
            my $dif = $lat - 90;
            $lat = 90 - $dif;
            $rundirect = $rundirect + 180; #グローバル変数に方向性を変更
            return $lat;
         }
    return $lat; # スルーの場合
}

# -180 < $lng < 180
sub overArealng {
    my ($lng) = shift;

        if ( $lng > 180 ) {
            my $dif = $lng - 180;
            $lng = -180 + $dif;
            return $lng;
            }
        if ( -180 > $lng ) {
            my $dif = abs($lng) - 180;
               $lng = 180 - $dif;
            return $lng;
           }
    return $lng; # スルーの場合
}


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
      $ua->websocket('wss://www.backbone.site/walkworld' => sub {
          my ($ua,$tx) = @_;
              iconchg($npcuser_stat->{status});
              sendjson($tx);
              $oncerun = "false";   
        }); 
      }

#ループ処理 websocketも再接続される 10secで更新に変更 追いかけっこしない想定なら60秒も有り
    Mojo::IOLoop->recurring(
                     10 => sub {
                           my $loop = shift;

                           $lifecount--;
                           if ( $lifecount == 0 ) {
                             say "時間切れで終了...";
                             exit;
                             }

    Loging("lifecount: $lifecount");

# websocketでの位置情報送受信
  $ua->websocket('wss://www.backbone.site/walkworld' => sub {
    my ($ua,$tx) = @_;

    $tx->on(json => sub {
        my ($tx,$hash) = @_;

            if ( defined $hash->{chat} ) {
               # chatメッセージの受信はスルーする。
               return;
               }

            # 終了判定
            if ( defined $hash->{to} ){
                if ( $hash->{to} eq $userid ) {

                    my $delay = Mojo::IOLoop::Delay->new;
                       $delay->steps(

                       sub {
                        my $delay = shift;
                            Mojo::IOLoop->timer(5 => $delay->begin);
                            Loging("$username 祓われた。。。");

                            my $hitparam = { to => $hash->{to}, execute => $hash->{execute}, hitname => $username, execemail => $hash->{execemail} };
                            $tx->send({ json => $hitparam });

                            my $txtmsg = "そして$username は祓われた！";
                            $chatobj->{chat} = $txtmsg;
                            sendchatobj($tx);
                       },
                       sub {
                        my ($delay,@param) = @_;
                        # 停止のdelay
                        exit;

                       })->wait;

               } else { return; } # 自分のUIDでなければパスする。
             }

         Loging("webSocket responce! $email : $npcuser_stat->{status}");
            $pointlist = $hash->{pointlist};
            $targetlist = clone($pointlist);

     # Makerがある場合の処理 targetをmakerに変更してstatをchaseに
        foreach my $poi ( @$pointlist ) {

           if ( $poi->{name} eq "maker" ) {

              # targetが既にmakerならlast
              if ( $npcuser_stat->{target} eq $poi->{userid}) {
                  last;
                 }

              $npcuser_stat->{target} = $poi->{userid};
              $npcuser_stat->{status} = "chase";
              Loging("Mode change Chase!");
              sendjson($tx);
              return;
              } 
        }

        }); #on json
    
    $tx->on(finish => sub {
       my ($tx, $code, $reason) = @_;
       Loging("WebSocket closed with status $code. $username");
       $tx->finish;
    #   exit;
    });

             # テスト用　位置保持
             if ( $npcuser_stat->{status} eq "STAY") {
                 iconchg($npcuser_stat->{status});
                 sendjson($tx);

                 $txtmsg = "STAYですよ！!";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 return;
                }

             my $rundirect = $npcuser_stat->{rundirect};

             # ランダム移動処理
             if ( $npcuser_stat->{status} eq "random" ){

                my $runway_dir = 1;

                if ($rundirect < 90) { $runway_dir = 1; }
                if (( 90 <= $rundirect)&&( $rundirect < 180)) { $runway_dir = 2; }
                if (( 180 <= $rundirect)&&( $rundirect < 270 )) { $runway_dir = 3; }
                if (( 270 <= $rundirect)&&( $rundirect < 360 )) { $runway_dir = 4; }

                if ( geoarea($lat,$lng) == 1 ) {

                if ($runway_dir == 1) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          if ($rundirect < 0 ) {
                             $rundirect = $rundirect + 360;
                             }
                          }
                if ($runway_dir == 2) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          }
                if ($runway_dir == 3) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          }
                if ($runway_dir == 4) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int($direct_reng/2);
                          if ($rundirect > 360 ) {
                             $rundirect = $rundirect - 360;
                             }
                          }
                } elsif ( geoarea($lat,$lng) == 2 ) {

                   # 保留

                } elsif ( geoarea($lat,$lng) == 3 ) {

                   # 保留

                } elsif ( geoarea($lat,$lng) == 4 ) {

                   # 保留

                }  # geoarea if


                # モード変更チェック 
                if (int(rand(10)) > 7) {
                        $npcuser_stat->{status} = "search";
                        Loging("Mode change Search!");
                        sendjson($tx);

                        $txtmsg = "Searchモードに変わったよ！";
                        $chatobj->{chat} = $txtmsg;
                        sendchatobj($tx);

                        return;
                   }

             } # if stat random

             # 検索モード
             if ( $npcuser_stat->{status} eq "search" ){

               if ($npcuser_stat->{place}->{name} eq "") {

                   my $selnum = int(rand($#keyword));
                   my $keywd = $keyword[$selnum];
                   Loging("DEBUG: $selnum : $keywd");

                  # target select
                   my $resjson = $ua->get("https://maps.googleapis.com/maps/api/place/nearbysearch/json?location=$lat,$lng&radius=$radi&key=$apikey&keyword=$keywd")->res->json;

                    undef $selnum;
                    undef $keywd;

                    if ( $resjson->{status} eq "ZERO_RESULTS" ) {
                               Loging("Null responce!");       

                               $npcuser_stat->{status} = "random";
                               $npcuser_stat->{place}->{name} = "";
                               $npcuser_stat->{place}->{lat} = "";
                               $npcuser_stat->{place}->{lng} = "";
                               Loging("Mode change random!");
                               sendjson($tx);
                               return;
                       }

                    my $list = $resjson->{results};
                    my @pointlist = @$list;
                    my $slice = int(rand($#pointlist));
                    Loging("slice: $slice");
                    my $deb = to_json($pointlist[$slice]);
                    Loging("DEBUG: slice: $deb");

                    $npcuser_stat->{place}->{lat} = $pointlist[$slice]->{geometry}->{location}->{lat} + 0;
                    $npcuser_stat->{place}->{lng} = $pointlist[$slice]->{geometry}->{location}->{lng} + 0;
                    $npcuser_stat->{place}->{name} = $pointlist[$slice]->{name};


                    my $txtmsg = "今から$npcuser_stat->{place}->{name}へ行くよ！";
                    $chatobj->{chat} = $txtmsg;
                    sendchatobj($tx);

                    Loging("DEBUG: Place: $npcuser_stat->{place}->{name} $npcuser_stat->{place}->{lat} $npcuser_stat->{place}->{lng}"); 

                } # if nameが空ならば

                # move
                my $runway_dir = 1;

                   $rundirect = geoDirect($npcuser_stat->{loc}->{lat}, $npcuser_stat->{loc}->{lng}, $npcuser_stat->{place}->{lat}, $npcuser_stat->{place}->{lng});
                Loging("DEBUG: rundirect: $rundirect ");

                if ($rundirect < 90) { $runway_dir = 1; }
                if (( 90 <= $rundirect)&&( $rundirect < 180)) { $runway_dir = 2; }
                if (( 180 <= $rundirect)&&( $rundirect < 270 )) { $runway_dir = 3; }
                if (( 270 <= $rundirect)&&( $rundirect < 360 )) { $runway_dir = 4; }

                Loging("DEBUG: runway_dir: $runway_dir ");

                if ( geoarea($lat,$lng) == 1 ) {

                if ($runway_dir == 1) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);
                          }
                if ($runway_dir == 2) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);
                          }
                if ($runway_dir == 3) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          }
                if ($runway_dir == 4) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          }
                } elsif ( geoarea($lat,$lng) == 2 ) {

                  # 保留

                } elsif ( geoarea($lat,$lng) == 3 ) {

                  # 保留

                } elsif ( geoarea($lat,$lng) == 4 ) {

                  # 保留

                } # geoarea if


                # radianに変換
                sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }
                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($npcuser_stat->{place}->{lng}, $npcuser_stat->{place}->{lat});
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                Loging("DEBUG: dist: $t_dist");

                spnchange($t_dist);

               if ( $t_dist < 5 ) {
                   $point_spn = 0.0002;  #元に戻す
                   $npcuser_stat->{status} = "random";
                   $npcuser_stat->{place}->{name} = "";
                   $npcuser_stat->{place}->{lat} = "";
                   $npcuser_stat->{place}->{lng} = "";
                   Loging("Mode change random!");
                   sendjson($tx);

                   $txtmsg = "Randomモードに変わったよ！";
                   $chatobj->{chat} = $txtmsg;
                   sendchatobj($tx);

                   return;
               }

             } # search

    # 追跡モード
      my $target = $npcuser_stat->{target};  # targetのUIDが入る クリアされるまで固定
      my $t_obj;   # targetのステータス 毎度更新される
         $targets = []; #targetlistからの入れ替え用
             #自分をリストから除外する
             while (my $i = shift(@$targetlist)){
                 if ( $i->{userid} eq $npcuser_stat->{userid}){
                     next;
                     }   
                     push(@$targets,$i);
                 }   
             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Targets $#chk_targets ");
             undef @chk_targets; # clear

       if ( $npcuser_stat->{status} eq "chase" ){

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                }   
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }   
                     }   

              # ターゲットをロストした場合、$targetをクリアして、randomに変更
              if ( $t_obj->{name} eq "" ) {
                 $target = "";
                 $npcuser_stat->{target} = "";
                 $npcuser_stat->{status} = "random";

                 # 送信処理
                 sendjson($tx);
                 return;
                 }

              my $deb_obj = to_json($t_obj);
              Loging("DEBUG: ======== $deb_obj ========");

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              Loging("DEBUG: lat: $lat lng: $lng");
              Loging("DEBUG: t_lat: $t_lat t_lng: $t_lng");


              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);
                 $rundirect = $t_direct;

              Loging("Chase Direct: $t_direct Distace: $t_dist ");

              spnchange($t_dist);

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              if ( geoarea($lat,$lng) == 1 ) {

              # 追跡は速度を多めに設定 50m以上離れている場合は高速モード
              if ($runway_dir == 1) {
                 if ( $t_dist > 50 ) {
                        $lat = $lat + rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat + rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                          }}
              if ($runway_dir == 2) {
                 if ( $t_dist > 50 ){
                        $lat = $lat - rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 3) {
                 if ( $t_dist > 50 ){
                        $lat = $lat - rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 4) {
                 if ( $t_dist > 50 ){
                        $lat = $lat + rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat + rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              } elsif ( geoarea($lat,$lng) == 2 ) {

                #保留

              } elsif ( geoarea($lat,$lng) == 3 ) {

                #保留

              } elsif ( geoarea($lat,$lng) == 4 ) {

                #保留

              } # geoarea if


              # 10m以下に近づくとモードを変更
              if ($t_dist < 10 ) {
                 $npcuser_stat->{status} = "random";
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 }

             } # if chase

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

# chat用　送信
sub sendchatobj {
           my $tx = shift;
                  $chatobj->{loc}->{lat} = $lat;
                  $chatobj->{loc}->{lng} = $lng;
              #    $chatobj->{chat} = encode_utf8($chatobj->{chat});
                  $chatobj->{geometry}->{coordinates}= [ $lng, $lat ];
                  $tx->send( { json => $chatobj } );
                  Loging("sendchatobj: $chatobj->{chat}");
                  return;
}


              # 送信処理 random search 共通
          #    $timerecord = DateTime->now()->epoch();
          #    $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
          #    $npcuser_stat->{time} = $timerecord;

              $npcuser_stat->{geometry}->{coordinates}= [ $lng, $lat ];
              $npcuser_stat->{loc}->{lat} = $lat;
              $npcuser_stat->{loc}->{lng} = $lng; 
              $npcuser_stat->{rundirect} = $rundirect;

              iconchg($npcuser_stat->{status});

              Loging("DEBUG: lat: $lat ( $npcuser_stat->{loc}->{lat} )  lng: $lng ( $npcuser_stat->{loc}->{lng} )");

           #   $tx->send( { json => $npcuser_stat } );
              sendjson($tx);
              return;
          }); #ループ

          $tx->finish if ($tx->is_websocket);

   }); # ua websocket

   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

