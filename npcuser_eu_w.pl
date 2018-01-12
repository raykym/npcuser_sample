#!/usr/bin/env perl

# user emurate webでの一般ユーザと同じように動くが、トラップは無い
# 3km圏内のユーザ数に応じてghostの出現数を調整
#
# npcuser_eu_w.pl [email] [emailpass] {lat} {lng} {mode}
# email passwordは必須
# websocket1個でchatまで対応した版
# 緯度経度の限界処理追加

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
use EV;
use AnyEvent;

use lib '/home/debian/perlwork/mojowork/server/ghostman/lib/Ghostman/Model';
use Sessionid;

$| = 1;

my $server = "westwind.backbone.site";  # dns lookup

# npcuser用モジュール

if ( $#ARGV < 1 ) {
    say "npcuser_eu_w.pl [email] [emailpass] {lat} {lng} {mode}";
    exit;
}


my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);
#   $ua->max_connections(1);
#   $ua->connect_timeout(1);
#   $ua->inactivity_timeout(1);

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
my $tx = $ua->post("https://$server/signinact" => form => { email => "$email", password => "$emailpass" });

if (my $res = $tx->success){ say $res->body }
   else {
      my $err = $tx->error;
      die "$err->{code} responce: $err->{message}" if $err->{code};
      die "Connection error: $err->{message}";
}

my $username = "";
my $userid = "";

  $tx = $ua->get("https://$server/walkworld/view");
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
my $point_spn = 0.0002; # /10sec
my $direct_reng = 90;
my $rundirect = int(rand(360));

# categoryはUSERで。
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
          "category" => "USER",
           };

my $txtmsg = "dumm";
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

# $runmodeが重複しているから注意   euでは登録アカウント情報に従う
sub iconchg {
    my $runmode = shift;
#if ( $runmode eq "random"){
#     $npcuser_stat->{icon_url} = "/img/ghost2_32px.png";
#    } elsif ( $runmode eq "chase"){ 
#     $npcuser_stat->{icon_url} = "/img/ghost4_32px.png";
#    } elsif ( $runmode eq "runaway" ){
#     $npcuser_stat->{icon_url} = "/img/ghost3_32px.png";
#    } elsif ( $runmode eq "round" ){
#     $npcuser_stat->{icon_url} = "/img/ghost1_32px.png";
#    } elsif ( $runmode eq "STAY"){ 
#     $npcuser_stat->{icon_url} = "/img/ghost2_32px.png";
#    }
    
}

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
             my $debmsg = to_json($npcuser_stat);
                 Loging("SENDJSON: $debmsg");
                 $tx->send( { json => $npcuser_stat } );
                 return;
}

# chat用　送信
sub sendchatobj {
           my $tx = shift;
                  $chatobj->{loc}->{lat} = $lat;
                  $chatobj->{loc}->{lng} = $lng;
                  $chatobj->{geometry}->{coordinates}= [ $lng, $lat ];
           #       $chatobj->{chat} = encode_utf8($chatobj->{chat});
               my $debmsg = to_json($chatobj);
                  Loging("SENDCHATJSON: $debmsg");
                  $tx->send( { json => $chatobj } );
                  return;
}

sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }

my $pointlist;
my $targetlist;
my $targets = [];
my $oncerun = "true";

   if ($oncerun) {
      # 1回のみ送信  起動時初回の位置情報を送信
      $ua->websocket("wss://$server/walkworld" => sub {
          my ($ua,$tx) = @_;
              iconchg($npcuser_stat->{status});
              sendjson($tx);
              $oncerun = "false";
              Loging("send Once!");
           $tx->finish;
        });
      }

my $txw;

#ループ処理 
my $cv = AE::cv;  # Mojo::IOLoop recurringでは判定が重複してしまう。
 my $t = AnyEvent->timer( after => 10,
                          interval => 10,
                             cb => sub {
                           
                         #  $lifecount--;    # 期間無制限
                           if ( $lifecount == 0 ) {
                             Loging("時間切れで終了...");
                             exit;
                             }
  Loging("life count: $lifecount ");

# websocketでの位置情報送受信
  $txw = $ua->websocket("wss://$server/walkworld" =>  sub {

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

                                Mojo::IOLoop->singleton;
                    my $delay = Mojo::IOLoop::Delay->new;
                       $delay->steps(

                       sub {
                        my $delay = shift;
                            Mojo::IOLoop->timer(1 => $delay->begin);
                            Loging("$username 祓われた。。。");

                            my $hitparam = { to => $hash->{to}, execute => $hash->{execute}, hitname => $username, execemail => $hash->{execemail} };
                            $tx->send({ json => $hitparam });

                            my $txtmsg = "そして$username は祓われた！";
                            $chatobj->{chat} = $txtmsg;
                            sendchatobj($tx);
                       },
                       sub {
                        my ($delay,@param) = @_;

                        exit;

                       })->wait;

               } else { return; } # 自分のUIDでなければパスする。
             } #if defined to

         Loging("webSocket responce! $email : $npcuser_stat->{status}");
            $pointlist = $hash->{pointlist};
            $targetlist = clone($pointlist);

         # ユニットを追加する
         my @gaccunit = ();
         my @userunit = ();
         for my $i (@$pointlist){
             if ( $i->{category} eq "NPC"){
                 push(@gaccunit,$i);
             } 
             if ( $i->{category} eq "USER"){
                 push(@userunit,$i);
             } 
         }

         my $unitcnt;

         if ( $#userunit < 5 ) {

                $unitcnt = 5;

             } elsif ( $#userunit >= 5 ) {

                $unitcnt = 10;

             }

         if ( $#gaccunit < $unitcnt ){
             $ua->post("https://$server/ghostman/gaccput" => form => { c => "1", lat => "$lat", lng => "$lng" });
             Loging("SET UNIT ADD!!!!"); 
         } 

     # 確率でMakerをセットする
     if ( $lifecount == int(rand(60480))){

         # maker固有のuidを設定 
         my $makeruid = Sessionid->new($userid)->uid;

         my $maker_stat = {
                   geometory => { 
                                type => "point",
                                coordinates => [ $lng,$lat ]
                               },   
                         loc => { 
                                 lat => $lat,
                                 lng => $lng 
                                         },   
                      name => "maker",
                      category => "MAKER",
                      userid => $makeruid,
                      status => "Dummy",
                      time => DateTime->now(),
                      icon_url => "/img/lighthouse3.png",
                 };   

             $maker_stat->{ttl} = DateTime->now();
          my $putmaker = { putmaker => $maker_stat }; 

             $tx->send({ json => $putmaker });
             Loging("DEBUG: Maker SET!!!");

     } # if $lifecount

     # デバッグ用
     #    while (my $linejson = shift(@$pointlist)) { 
     #      my $i = to_json($linejson);
     #      say "$i";
     #    }
     #    $tx->finish;

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
              last;
              } # if
        }

        }); #on json
    
    $tx->on(finish => sub {
       my ($tx, $code, $reason) = @_;
       Loging("WebSocket closed with status $code. $username");
    #   exit;
    });

             # テスト用　位置保持
             if ( $npcuser_stat->{status} eq "STAY") {
                 iconchg($npcuser_stat->{status});
                 sendjson($tx);

                 $txtmsg = "STAY desuyo!";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 return;
                }

             my $rundirect = $npcuser_stat->{rundirect};

             my $runway_dir;

             # ランダム移動処理
             if ( $npcuser_stat->{status} eq "random" ){

                #周囲にユニットが在るか確認
                     $targets = [];
                     for my $i (@$targetlist){
                         #自分をリストから除外する
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                             next;
                         }
                         # USERを除外
                         if ( $i->{category} eq "USER"){
                             next;
                         } 
                         # makerを除外
                         if ( $i->{name} eq "maker"){
                             next;
                         } 
                         push(@$targets,$i);
                     }
                my @chk_targets = @$targets;

                $runway_dir = 1 if ( ! defined $runway_dir);

                if ($rundirect < 90) { $runway_dir = 1; }
                if (( 90 <= $rundirect)&&( $rundirect < 180)) { $runway_dir = 2; }
                if (( 180 <= $rundirect)&&( $rundirect < 270 )) { $runway_dir = 3; }
                if (( 270 <= $rundirect)&&( $rundirect < 360 )) { $runway_dir = 4; }

             if ( geoarea($lat,$lng) == 1){
                # 東経北緯
                if ($runway_dir == 1) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);        #規定値超え判定 rundirectも変更している
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);        #規定値超え判定
                          $rundirect = $rundirect + int(rand($direct_reng)) - int(rand($direct_reng));
                          if ($rundirect < 0 ) {
                             $rundirect = $rundirect + 360;
                             }
                          }
                if ($runway_dir == 2) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng + rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int(rand($direct_reng));
                          }
                if ($runway_dir == 3) {
                          $lat = $lat - rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int(rand($direct_reng));
                          }
                if ($runway_dir == 4) {
                          $lat = $lat + rand($point_spn);
                          $lat = overArealat($lat);
                          $lng = $lng - rand($point_spn);
                          $lng = overArealng($lng);
                          $rundirect = $rundirect + int(rand($direct_reng)) - int(rand($direct_reng));
                          if ($rundirect > 360 ) {
                             $rundirect = $rundirect - 360;
                             }
                          }
                } elsif ( geoarea($lat,$lng) == 2 ) {
                # 西経北緯

                  #保留

                } elsif ( geoarea($lat,$lng) == 3 ) {
                # 東経南偉

                  #保留

                } elsif ( geoarea($lat,$lng) == 4 ) {
                # 西経南偉

                  #保留

                } # geoarea if


                # モード変更チェック 
                   if (int(rand(10)) > 5) {

                        if ($#chk_targets == -1) { return; }

                        $npcuser_stat->{status} = "chase";
                        Loging("Mode change Chase!");
                        sendjson($tx);

                        my $txtmsg  = "追跡モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   sendchatobj($tx);
                        return;
                   }

       # euではrandomとchaseのみ
                #   } elsif (int(rand(10)) > 6 ) {

                #        if ($#chk_targets == -1) { return; }

                #        $npcuser_stat->{status} = "round";
                #        Loging("Mode change Round!");
                #        sendjson($tx);

                #        my $txtmsg  = "周回モードになったよ！";
                #        $chatobj->{chat} = $txtmsg;
                #        sendchatobj($tx);
                     #   return;
                #   } elsif (int(rand(10)) > 8 ) {

                #        if ($#chk_targets == -1) { return; }

                #        $npcuser_stat->{status} = "runaway";
                #        Loging("Mode change Runaway!");
                #        sendjson($tx);

                #        my $txtmsg  = "逃走モードになったよ！";
                #        $chatobj->{chat} = $txtmsg;
                #        sendchatobj($tx);
                     #   return;
                #   }

                #スタート地点からの距離判定
                # radianに変換
            #    my @s_p = NESW($lng, $lat);
            #    my @t_p = NESW($s_lng, $s_lat);
            #    my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
            #    Loging("mode Random: $t_dist");
            #    spnchange($t_dist);

                @chk_targets = @$targets;
                Loging("DEBUG: Targets $#chk_targets ");

                # スタート地点から2km離れて、他に稼働するものがあれば、
            #    if ($t_dist > 2000 ){
            #         $targets = [];
            #         #自分をリストから除外する
            #         for my $i (@$targetlist){
            #             if ( $i->{userid} eq $npcuser_stat->{userid}){
            #             next;
            #             }
            #             push(@$targets,$i);
            #         }
            #        my @t_list = @$targets;
            #        if ( $#t_list > 2 ){
            #           $npcuser_stat->{status} = "chase";
            #           Loging("Mode change Chase!");
            #           my $txtmsg  = "追跡モードになったよ！";
            #           $chatobj->{chat} = $txtmsg;
            #           sendchatobj($tx);
            #           }
            #    } # $t_dist > 2000  

            #   if (($npcuser_stat->{status} eq "random") && ( $#chk_targets > 20 )) {
            #     # runawayモードへ変更
            #            $npcuser_stat->{status} = "runaway";
            #            Loging("Mode change Runaway!");
            #            sendjson($tx);
            #            my $txtmsg  = "逃走モードになったよ！";
            #            $chatobj->{chat} = $txtmsg;
            #            sendchatobj($tx);
            #        #    return;
            #      }

             #    undef @chk_targets; # clear 

             } # if stat random

    # 追跡モード
      my $target = $npcuser_stat->{target};  # targetのUIDが入る クリアされるまで固定
      my $t_obj;   # targetのステータス 毎度更新される
         $targets = []; #targetlistからの入れ替え用
         for my $i (@$targetlist){
             #自分をリストから除外する
             if ( $i->{userid} eq $npcuser_stat->{userid}){
                 next;
                 }
                 # USERを除外
                 if ( $i->{category} eq "USER"){
                     next;
                 } 
                 push(@$targets,$i);
             }

       if ( $npcuser_stat->{status} eq "chase" ){

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Targets $#chk_targets ");

             if (($target eq "")&&($#chk_targets > 0)) {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                }

          # eu用　20m以内のunitをお祓いする
          my @eutargets;
          for my $i (@$targets){
                 # makerを除外
                 if ( $i->{name} eq "maker"){
                     next;
                 } 
                # category USERは除外済想定
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($i->{loc}->{lng}, $i->{loc}->{lat});
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);

              if ($t_dist > 20 ){
              # 20m以上は除外
                  next;
              }

              push(@eutargets,$i);

              undef @s_p;
              undef @t_p;
              undef $t_dist;
          }

          if (@eutargets){
              for my $i (@eutargets){
                  my $hit_param = { to => $i->{userid}, execute => $userid, execemail => $email };
                  my $debug = to_json($hit_param);
                  Loging("DEBUG: hit_param: $i->{name} 攻撃した $debug");
                  $tx->send( { json => $hit_param } );
              }

          } # if


             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、random-mode
              if ( ! defined $t_obj->{name} ) {
                 $npcuser_stat->{status} = "random";
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
              #   sendchatobj($tx);

               #  return;
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
                        $lat = $lat + rand($point_spn + 0.0001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.0001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat + rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 2) {
                 if ( $t_dist > 50 ){
                        $lat = $lat - rand($point_spn + 0.0001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.0001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 3) {
                 if ( $t_dist > 50 ){
                        $lat = $lat - rand($point_spn + 0.0001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.0001);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 4) {
                 if ( $t_dist > 50 ){
                        $lat = $lat + rand($point_spn + 0.0001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.0001);
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


              # 5m以下に近づくとモードを変更   その前にターゲットを攻撃してターゲットをロストする想定
              if ($t_dist < 5 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
              #   sendchatobj($tx);
                 }


           #    if (($npcuser_stat->{status} eq "chase") && ( $#chk_targets > 20 )) {
           #      # runawayモードへ変更
           #             $npcuser_stat->{status} = "runaway";
           #             Loging("Mode change Runaway!");
           #             sendjson($tx);
           #             my $txtmsg  = "逃走モードになったよ！";
           #             $chatobj->{chat} = $txtmsg;
           #             sendchatobj($tx);
           #          #   return;
           #       }

         #    undef @chk_targets; # clear

             } # if chase

       # 逃走モード
       if ( $npcuser_stat->{status} eq "runaway" ){

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Targets $#chk_targets ");

             if (($target eq "")&&($#chk_targets > 0)) {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("RUNAWAY target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                }

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、random-mode
              if (! defined $t_obj->{name} ) {
                 $npcuser_stat->{status} = "random";
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 return;
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: RUNAWAY ======== $deb_obj ========"); 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              Loging("DEBUG: RUNAWAY: lat: $lat lng: $lng");
              Loging("DEBUG: RUNAWAY: t_lat: $t_lat t_lng: $t_lng");

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

              Loging("RUNAWAY Direct: $t_direct Distace: $t_dist ");

              spnchange($t_dist);
        
                 $rundirect = $t_direct;

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              if ( geoarea($lat,$lng) == 1 ) {

              if ($runway_dir == 1) {
                        $lat = $lat + rand($point_spn + 0.0002);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.0002);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn + 0.0002);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.0002);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn + 0.0002);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.0002);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn + 0.0002);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.0002);
                        $lng = overArealng($lng);
                          }

              } elsif ( geoarea($lat,$lng) == 2 ) {

                 #保留

              } elsif ( geoarea($lat,$lng) == 3 ) {

                 #保留

              } elsif ( geoarea($lat,$lng) == 4 ) {

                 #保留

              } # geoarea if

              #ターゲットが規定以下の場合は
              if ( ($#chk_targets < 20) && (int(rand(10) > 7))) {
                    $npcuser_stat->{status} = "round";
                    Loging("Mode change Round!");
                    sendjson($tx);

                    my $txtmsg  = "周回モードになったよ！";
                    $chatobj->{chat} = $txtmsg;
                    sendchatobj($tx);

              # 1500m以上に離れるとモードを変更
              } elsif (($t_dist > 1500 ) || ($#chk_targets > 20)) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 }

          #   undef @chk_targets; # clear
          } # runaway

       # 周回動作
       if ( $npcuser_stat->{status} eq "round" ){

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Targets $#chk_targets ");

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("ROUND target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                }
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
              # ターゲットをロストした場合、random-mode
              if ( ! defined $t_obj->{name} ) {
                 $npcuser_stat->{status} = "random";
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: ROUND ======== $deb_obj ========"); 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

              Loging("DEBUG: ROUND: lat: $lat lng: $lng");
              Loging("DEBUG: ROUND: t_lat: $t_lat t_lng: $t_lng");

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);

              # spnchangeは行わない

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
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              if ( geoarea($lat,$lng) == 1 ) {

              # 周回は速度を上乗せ
              if ($runway_dir == 1) {
                        $lat = $lat + rand($point_spn+0.0003);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn+0.0003);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn+0.0003);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn+0.0003);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn+0.0003);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn+0.0003);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn+0.0003);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn+0.0003);
                        $lng = overArealng($lng);
                          }
              } elsif ( geoarea($lat,$lng) == 2 ) {

                 # 保留

              } elsif ( geoarea($lat,$lng) == 3 ) {

                 # 保留

              } elsif ( geoarea($lat,$lng) == 4 ) {

                 # 保留

              } # geoarea if

              if ( int(rand(100)) > 90 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
                 sendchatobj($tx);
                 } 

           if (($npcuser_stat->{status} eq "round") && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        sendjson($tx);
                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                        sendchatobj($tx);
                        return;
                }

          #   undef @chk_targets; # clear

          } # round

              # 送信処理 random chase runaway round共通
          #時刻はsendjsonブロックで追加しているのコメントアウト
          #    $timerecord = DateTime->now()->epoch();
          #    $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
          #    $npcuser_stat->{time} = $timerecord;

              $npcuser_stat->{geometry}->{coordinates}= [ $lng, $lat ];
              $npcuser_stat->{loc}->{lat} = $lat;
              $npcuser_stat->{loc}->{lng} = $lng; 
              $npcuser_stat->{rundirect} = $rundirect;

              iconchg($npcuser_stat->{status});

          #    $tx->send( { json => $npcuser_stat } );
              sendjson($tx);
          #    return;
          }); #  ua

   }); # loop 

$cv->recv;
