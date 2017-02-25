#!/usr/bin/env perl

# 常時ws接続で考えていた仕様
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


# Login認証
my $tx = $ua->post('https://192.168.0.8/signinact' => form => { email => "$email", password => "$emailpass" });

if (my $res = $tx->success){ say $res->body }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}

my $username = "";
my $userid = "";

# 認証を通ればページはパスできる事を確認
  $tx = $ua->get('https://192.168.0.8/walkworld/view');
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
my $point_spn = 0.00015;
my $direct_reng = 90;
my $rundirect = int(rand(360));

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
          "target" => "",
           };

# アイコン変更処理
iconchg($npcuser_stat->{status});
# $runmodeが重複しているから注意
sub iconchg {
    my $runmode = shift;
if ( $runmode eq "random"){
     $npcuser_stat->{icon_url} = "/img/ghost2_32px.png";
    } elsif ( $runmode eq "chase"){ 
     $npcuser_stat->{icon_url} = "/img/ghost4_32px.png";
    } elsif ( $runmode eq "runaway" ){
     $npcuser_stat->{icon_url} = "/img/ghost3_32px.png";
    } elsif ( $runmode eq "round" ){
     $npcuser_stat->{icon_url} = "/img/ghost1_32px.png";
    }
}

# websocketでの位置情報送受信
  $ua->websocket('wss://192.168.0.8/walkworld' => sub {
    my ($ua,$tx) = @_;


    my $pointlist;
    my $targetlist;

    $tx->on(json => sub {
        my ($tx,$hash) = @_;

            # 終了判定
            if ( defined $hash->{to} ){
                say "祓われた。。。";
                $tx->finish;
                exit;
             }

         say "webSocket responce! $email : $npcuser_stat->{status}";
            $pointlist = $hash->{pointlist};
            $targetlist = clone($pointlist);
     #    while (my $linejson = shift(@$pointlist)) { 
     #      my $i = to_json($linejson);
     #      say "$i";
     #    }
     #    $tx->finish;
        }); #on json

       # とりあえず1回送信しておく
       #       $timerecord = DateTime->now()->epoch();
       #       $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
       #       $npcuser_stat->{time} = $timerecord;
       #       $tx->send( { json => $npcuser_stat } );
    
    $tx->on(finish => sub {
       my ($tx, $code, $reason) = @_;
       say "WebSocket closed with status $code.";
       $tx->finish;
       exit;
    });

       Mojo::IOLoop->recurring(
          60 => sub {

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
                if (int(rand(10)) > 9) {
                        $npcuser_stat->{status} = "chase";
                        say "Mode change Chase!";
                        sendjson($tx);
                        return;
                   } elsif (int(rand(10)) > 6 ) {
                        $npcuser_stat->{status} = "round";
                        say "Mode change Round!";
                        sendjson($tx);
                        return;
                   } elsif (int(rand(10)) > 6 ) {
                        $npcuser_stat->{status} = "runaway";
                        say "Mode change Runaway!";
                        sendjson($tx);
                        return;
                   }

                #スタート地点からの距離判定
                # radianに変換
                sub NESW { deg2rad($_[0]), deg2rad($_[1]) }
                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($s_lng, $s_lat);
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);

                say "mode Random: $t_dist";

                # スタート地点から2km離れて、他に稼働するものがあれば、
                if ($t_dist > 2000 ){
                     my @t_list = @$targetlist; #ここはtargetsでは無い
                     if ( $#t_list > 2 ){
                        $npcuser_stat->{status} = "chase";
                        say "Mode change Chase!";
                        }
                }

             } # if stat random

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

    # 追跡モード
      my $target = $npcuser_stat->{target};  # targetのUIDが入る クリアされるまで固定
      my $t_obj;   # targetのステータス 毎度更新される
      my $targets = []; #targetlistからの入れ替え用
             #自分をリストから除外する
             while (my $i = shift(@$targetlist)){
                 if ( $i->{userid} eq $npcuser_stat->{userid}){
                     next;
                     }
                     push(@$targets,$i);
                 }

       if ( $npcuser_stat->{status} eq "chase" ){

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     say "target: $target : $lc : $tnum : $t_list[$tnum]->{name}"; 
                }
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、$targetをクリアして、リターン
              if ( $t_obj->{name} eq "" ) {
                 $target = "";
                 $npcuser_stat->{target} = "";

                 # 送信処理
                 sendjson($tx);
                 }

              my $deb_obj = to_json($t_obj); 
              say "DEBUG: ======== $deb_obj ========"; 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              say "DEBUG: lat: $lat lng: $lng";
              say "DEBUG: t_lat: $t_lat t_lng: $t_lng";


              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);
                 $rundirect = $t_direct;

              say "Chase Direct: $t_direct Distace: $t_dist ";

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 < $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 < $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 < $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              # 追跡は速度を多めに設定 500m以上離れている場合は高速モード
              if ($runway_dir == 1) {
                 if ( $t_dist > 500 ) {
                        $lat = $lat + rand($point_spn+0.001);
                        $lng = $lng + rand($point_spn+0.001);
                    } else {
                        $lat = $lat + rand($point_spn+0.00005);
                        $lng = $lng + rand($point_spn+0.00005);
                          }}
              if ($runway_dir == 2) {
                 if ( $t_dist > 500 ){
                        $lat = $lat - rand($point_spn+0.001);
                        $lng = $lng + rand($point_spn+0.001);
                    } else {
                        $lat = $lat - rand($point_spn+0.00005);
                        $lng = $lng + rand($point_spn+0.00005);
                          }}
              if ($runway_dir == 3) {
                 if ( $t_dist > 500 ){
                        $lat = $lat - rand($point_spn+0.001);
                        $lng = $lng - rand($point_spn+0.001);
                    } else {
                        $lat = $lat - rand($point_spn+0.00005);
                        $lng = $lng - rand($point_spn+0.00005);
                          }}
              if ($runway_dir == 4) {
                 if ( $t_dist > 500 ){
                        $lat = $lat + rand($point_spn+0.001);
                        $lng = $lng - rand($point_spn+0.001);
                    } else {
                        $lat = $lat + rand($point_spn+0.00005);
                        $lng = $lng - rand($point_spn+0.00005);
                          }}
              # 10m以下に近づくとモードを変更
              if ($t_dist < 10 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 say "Mode Change........radom.";
                 }

             } # if chase

       # 逃走モード
       if ( $npcuser_stat->{status} eq "runaway" ){

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     say "RUNAWAY target: $target : $lc : $tnum : $t_list[$tnum]->{name}"; 
                }
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、$targetをクリアして、リターン
              if ( $t_obj->{name} eq "" ) {
                 $target = "";
                 $npcuser_stat->{target} = "";

                 # 送信処理
                 sendjson($tx);
                 }

              my $deb_obj = to_json($t_obj); 
              say "DEBUG: RUNAWAY ======== $deb_obj ========"; 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              say "DEBUG: RUNAWAY: lat: $lat lng: $lng";
              say "DEBUG: RUNAWAY: t_lat: $t_lat t_lng: $t_lng";

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);

                 #逆方向へ設定
                 if ( $t_direct > 180 ) {
                    $t_direct = $t_direct - 180 + int(rand(45)) - int(rand(45));
                    if ( $t_direct < 0 ) { $t_direct = $t_direct + 45; }
                    } else {
                    $t_direct = $t_direct + 180 + int(rand(45)) - int(rand(45));
                    if ($t_direct > 360) { $t_direct = $t_direct - 45; }
                    }

              say "RUNAWAY Direct: $t_direct Distace: $t_dist ";
        
                 $rundirect = $t_direct;

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 < $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 < $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 < $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

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

              # 1000m以上に離れるとモードを変更
              if ($t_dist > 1000 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 say "Mode Change........radom.";
                 }

          } # runaway

       # 周回動作
       if ( $npcuser_stat->{status} eq "round" ){

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     say "ROUND target: $target : $lc : $tnum : $t_list[$tnum]->{name}"; 
                }
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
              # ターゲットをロストした場合、$targetをクリアして、リターン
              if ( $t_obj->{name} eq "" ) {
                 $target = "";
                 $npcuser_stat->{target} = "";

                 # 送信処理
                 sendjson($tx);
                 }

              my $deb_obj = to_json($t_obj); 
              say "DEBUG: ROUND ======== $deb_obj ========"; 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              say "DEBUG: ROUND: lat: $lat lng: $lng";
              say "DEBUG: ROUND: t_lat: $t_lat t_lng: $t_lng";

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);

              my $round_dire = 1;
              # 低い確率で方向が変わる
              if ( rand(10) > 8 ) {
              if ( rand(10) > 5 ) { 
                                    $round_dire = 1;
                                   } else { 
                                    $round_dire = 2;
                  }
              } # out rand

              # 右回りプラス方向
              if ( $round_dire == 1 ) {
                  $t_direct = $t_direct + 90;
                  if ( $t_direct > 360 ) { $t_direct = $t_direct - 360; }
              } else {
                  # 左回りマイナス方向
                  $t_direct = $t_direct - 90;
                  if ( $t_direct < 0 ) { $t_direct = $t_direct + 360 ;}
                }
                $rundirect = $t_direct;

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 < $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 < $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 < $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }
              # 周回は速度を上乗せ
              if ($runway_dir == 1) {
                        $lat = $lat + rand($point_spn+0.001);
                        $lng = $lng + rand($point_spn+0.001);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn+0.001);
                        $lng = $lng + rand($point_spn+0.001);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn+0.001);
                        $lng = $lng - rand($point_spn+0.001);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn+0.001);
                        $lng = $lng - rand($point_spn+0.001);
                          }

              if ( int(rand(100)) > 90 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 say "Mode Change........radom.";
                 }

          } # round

              # 送信処理 random chase runaway round共通
              $timerecord = DateTime->now()->epoch();
              $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
              $npcuser_stat->{time} = $timerecord;

              $npcuser_stat->{geometry}->{coordinates}= [ $lng, $lat ];
              $npcuser_stat->{loc}->{lat} = $lat;
              $npcuser_stat->{loc}->{lng} = $lng; 
              $npcuser_stat->{rundirect} = $rundirect;

              iconchg($npcuser_stat->{status});

              $tx->send( { json => $npcuser_stat } );
          }); #ループ

   #接続維持の為
   Mojo::IOLoop->recurring(
          10 => sub {
            my $jsonobj = { "dummy" => "dummy" };
               $tx->send( { json => $jsonobj });
          });

   }); # ua websocket


   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

