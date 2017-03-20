#!/usr/bin/env perl

# site1を経由せずDBへ直接書き込みバージョン
# アカウント情報はredisから受け取り、個々の処理を行って、mongodb、redisへ位置情報を書き戻す
# 終了処理も此処で行い、mongodbとredisへ送信する
# 起動時に引数でsidを受け取る。postでこれを返す事でリストを得る
#
# 緯度経度の限界処理追加
# usage
# npcuser_n_sitedb.pl [ghostmanid]

use strict;
use warnings;
use utf8;
use feature 'say';
use Mojo::UserAgent;
use Mojo::JSON qw(encode_json decode_json from_json to_json);
use DateTime;
use Math::Trig qw(great_circle_distance rad2deg deg2rad pi);
use Clone qw(clone);
#use Mojo::IOLoop;
#use Mojo::IOLoop::Delay;
use MongoDB;
use Mojo::Redis2;
use Encode qw(encode_utf8 decode_utf8);
use Data::Dumper;
use Devel::Size qw/total_size/;
use Devel::Cycle;
use Scalar::Util qw(weaken);
use Devel::Peek;
use AnyEvent;

$| = 1;

# DB設定
my $mongoclient = MongoDB->connect('mongodb://dbs-1:27017');

my $redis ||= Mojo::Redis2->new(url => 'redis://dbs-1:6379');

my $wwdb = $mongoclient->get_database('WalkWorld');
my $timelinecoll = $wwdb->get_collection('MemberTimeLine');
my $trapmemberlist = $wwdb->get_collection('trapmemberlist');

my $wwlogdb = $mongoclient->get_database('WalkWorldLOG');
my $timelinelog = $wwlogdb->get_collection('MemberTimeLinelog');
my $membercount = $wwlogdb->get_collection('MemberCount');

# WalkChat用
my $holldb = $mongoclient->get_database('holl_tl');
my $walkchatcoll = $holldb->get_collection('walkchat');

my $chatname = 'WALKCHAT';
my $attackCH = 'ATTACKCHN';
my @chatArray = ( $attackCH ); # chatは受信させない

my @keyword = ( "コンビニ",
                "銀行",
                "役所",
                "スーパー",
                "駅",
                "図書館",
                "レストラン",
                "神社",
                "寺",
                "病院",
                "郵便局",
                "商店",
                "ストアー",
                "スタンド",
                "公園",
                "モール",
                "学校",
                "ファーストフード",
                "菓子", 
              );

my $apikey = "AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8";
my $radi = 3000; #検索レンジ

my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);

my $username = "";
my $userid = "";

my $ghostmanid = "$ARGV[0]";
   if ( !defined $ghostmanid ) {
        Loging("UNDEFINED ghostmanid!!!!!!!");
        exit;
       }

my $gacclist;
my $run_gacclist;

my $nullcount = 0;

# 初期値
my $lat = 35.677543 + rand(0.001) - (0.001/2);
my $lng = 139.9055707 + rand(0.001) - (0.001/2);
my $s_lat = clone($lat);
my $s_lng = clone($lng);
my $runmode = "random";

my $lifecount = 60480; #1week /10sec count 初期設定で利用、その後gacclistで置き換えられる

my $icon_url = ""; # 暫定
my $timerecord;
my $point_spn;
my $direct_reng = 90;
my $rundirect;

# $gacclistに内包
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
            "username" => "",
            "hms" => "",
            "icon_url" => "",
            "ttl" => "",
              };

my $pointlist;
my $targetlist;
my $targets;
my $oncerun = "true";
my @pointlist;




##### subs #####

# 表示用ログフォーマット
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

sub get_gacclist{
# リストの取得
    #redis経由に変更した為、直接取得する
    @$gacclist = ();
    $gacclist = $redis->get("GACC$ghostmanid");
    if ( defined $gacclist) {
        $gacclist = from_json($gacclist);
        } else {
               @$gacclist = ();
               }
   # my @list = @$gacclist;
   #    Loging("gacclist: $#list +1");
}

sub npcinit {
# パラメータの初期化 
    for my $acc (@$run_gacclist){
        $acc->{status} = "random" if ( $acc->{status} eq "");
      #  $acc->{status} = "STAY" if ( $acc->{status} eq "");
        $acc->{geometry}->{coordinates} = [ $lng , $lat ] if ( $acc->{geometry}->{coordinates} == [0,0] );
        $acc->{loc}->{lat} = clone($lat) if ( $acc->{loc}->{lat} == 0);
        $acc->{loc}->{lng} = clone($lng) if ( $acc->{loc}->{lng} == 0);
        $acc->{rundirect} = int(rand(360)) if ( $acc->{rundirect} eq "");
        $acc->{point_spn} = 0.0002 if ( $acc->{point_spn} eq "");
        $acc->{lifecount} = 60480 if ( $acc->{lifecount} eq "");
        $acc->{icon_url} = iconchg($acc->{status}) if ($acc->{icon_url} eq "");

     #   my $debug = to_json($acc);
     #   Loging("para init: $debug");
     #   undef $debug;
    }
}

# icon変更 
sub iconchg {
    my $runmode = shift;

 #   Loging("iconchg: runmode: $runmode");

    if ( $runmode eq "random"){
          my $icon_url = "/img/ghost2_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "chase"){ 
          my $icon_url =  "/img/ghost4_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "runaway" ){
          my $icon_url = "/img/ghost3_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "round" ){
          my $icon_url = "/img/ghost1_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "STAY"){ 
          my $icon_url = "/img/ghost2_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        } elsif ( $runmode eq "search"){
          my $icon_url = "/img/ghost4_32px.png";
      #    Loging("iconchg: $icon_url");
          undef $runmode;
          return $icon_url;
        }
          undef $runmode;
        return; #そのまま戻す
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

    undef $lat;
    undef $lng;

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
            undef $dif;
            return $lat;
         }
        # 北半球は超えても北半球
        if ( 90 < $lat ) {
            my $dif = $lat - 90;
            $lat = 90 - $dif;
            $rundirect = $rundirect + 180; #グローバル変数に方向性を変更
            undef $dif;
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
            undef $dif;
            return $lng;
            }
        if ( -180 > $lng ) {
            my $dif = abs($lng) - 180;
               $lng = 180 - $dif;
            undef $dif;
            return $lng;
           }
    return $lng; # スルーの場合
}

sub spnchange {
       my $t_dist = shift;
          if ( $t_dist > 50 ) {
               $point_spn = 0.0002;
           #    Loging("point_spn: $point_spn");
             } else {
               $point_spn = 0.0001;
           #    Loging("point_spn: $point_spn");
             }
       undef $t_dist;
}

sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }

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

    undef $lat1;
    undef $lng1;
    undef $lat2;
    undef $lng2;
    undef $Y;
    undef $X;
    undef $dirE0;

    return $dirN0;
    }

# 送信処理 npcuser_statを時刻チェックして送信する。
sub writejson {
    my $npcuser_stat = shift;
                  $timelinecoll->delete_many({"userid" => $npcuser_stat->{userid}}); # mognodb3.2 削除してから
             #    $timerecord = DateTime->now()->epoch();
             #    $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
             #    $npcuser_stat->{time} = $timerecord;
                 $npcuser_stat->{ttl} = DateTime->now();

                  $npcuser_stat->{geometry}->{coordinates} = [ $lng, $lat ];
                  $npcuser_stat->{loc}->{lat} = $lat;
                  $npcuser_stat->{loc}->{lng} = $lng; 
                  $npcuser_stat->{point_spn} = $point_spn;
                  $npcuser_stat->{rundirect} = $rundirect;
                  $npcuser_stat->{icon_url} = iconchg($npcuser_stat->{status});

             my $debmsg = to_json($npcuser_stat);
                 Loging("WRITE MONGODB: $debmsg");
                 $timelinecoll->insert_one($npcuser_stat);
                 $timelinelog->insert_one($npcuser_stat);

             undef $debmsg;

         #個別の更新で書き込んでおかないとダメな場合もあるか。。。？
         #    my $run_json = to_json($run_gacclist);
         #       $redis->set("GACC$ghostmanid" => $run_json);
         #       $redis->expire("GACC$ghostmanid" => 32 ); #32秒保持する
         #       undef $run_json;

              undef $npcuser_stat;
                 return;
}

# chat用　送信
sub writechatobj {
    my $npcuser_stat = shift;
               my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  $chatobj->{chat} = decode_utf8($chatobj->{chat});
                  $chatobj->{loc}->{lat} = $lat;
                  $chatobj->{loc}->{lng} = $lng;
                  $chatobj->{geometry}->{coordinates}= [ $lng, $lat ];
                  $chatobj->{username} = $npcuser_stat->{name};
                  $chatobj->{icon_url} = $npcuser_stat->{icon_url};
                  $chatobj->{hms} = $dt->hms;
                  $chatobj->{ttl} = DateTime->now();
               my $debmsg = to_json($chatobj);
                  Loging("WRITECHAT: $debmsg");
               my $chatjson = to_json($chatobj);
                  $redis->publish( $chatname , $chatjson );
                  $walkchatcoll->insert_one($chatobj);              

                  undef $debmsg;
                  undef $npcuser_stat;
                  undef $chatjson;
                  undef $dt;
                  
                  return;
}



# main ###############

get_gacclist();

# $gacclistと実行中のリストの分岐、 アカウントの削除は自前で追加のみチェックする
   # 差分が在れば追加
   foreach my $acc (@$gacclist){
               push(@$run_gacclist,$acc) unless grep { $_->{name} =~ $acc->{name} } @$run_gacclist;
           }
 #  my $debug = to_json($run_gacclist);
 #  Loging("run_gacclist: $debug");
 #  undef $debug;

npcinit();

# 初回マーク処理
    foreach my $npcuser_stat (@$run_gacclist){
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  # TTLレコードを追加する。
                  $username = $npcuser_stat->{name}; #Logingで利用されるため、設定だけしておく
                  $npcuser_stat->{ttl} = DateTime->now();
                  $timelinecoll->delete_many({"userid" => $npcuser_stat->{userid}}); # mognodb3.2 削除してから
                  $timelinecoll->insert_one($npcuser_stat);
                  $timelinelog->insert_one($npcuser_stat);
                  undef $dt;
    } # foreach $npcuser_stat

while (1) {
    my $cv = AnyEvent->condvar;

    my $t = AnyEvent->timer(
            after => 1,
            interval => 10,
               cb => sub {

#ループ処理 
 #   Mojo::IOLoop->recurring(
 #                    10 => sub {
 #                          my $loop = shift;

        Loging("------------------------------LOOP START-----------------------------------");

        # アカウントリストをチェックして差分を確認する
        get_gacclist();

        my @list = @$gacclist;
        if (!@list){
            $nullcount++;
            if ( $nullcount >= 3 ) {
                Loging("null account list 3 times!!!!");
                exit;
                }
        }
        undef @list;


        foreach my $acc (@$gacclist){
                   push(@$run_gacclist,$acc) unless grep { $_->{name} =~ $acc->{name} } @$run_gacclist;
               #    my $debug = to_json($acc);
               #    Loging("run_gacclist add: $debug") unless grep { $_->{name} =~ $acc->{name} } @$run_gacclist;
               #    undef $debug; 
               }
     #   @list = @$run_gacclist;
     #   Loging("run_gacclist count: $#list+1");
     #   undef @list;

        npcinit();

 #アカウント配列のループ
        foreach my $npcuser_stat (@$run_gacclist){

undef @pointlist;
undef $pointlist;
undef $targetlist;
undef $targets;

        #redisで攻撃判定の受信
        $redis->subscribe(\@chatArray, sub {
                      my ($redis, $err) = @_;
                    #     return $redis->publish( $chatname => $err) if $err;
                         Loging("DEBUG: $username redis subscribe");
                         return $redis->incr(@chatArray);
                      });
        $redis->expire( \@chatArray => 3600 );

        $redis->on(error => sub {
                      my ($redis,$err) = @_;
                         Loging("DEBUG: $username redis error: $err");
                      });

         # 共有変数へ、値をリンク
            $username = $npcuser_stat->{name};
            $userid = $npcuser_stat->{userid};
            $rundirect = $npcuser_stat->{rundirect};
            $lat = $npcuser_stat->{loc}->{lat};
            $lng = $npcuser_stat->{loc}->{lng}; 
            $point_spn = $npcuser_stat->{point_spn};

          #  my $debug = to_json($npcuser_stat);
          #  Loging("------LOOP npcuser_stat: $debug");
          #  undef $debug;


             Loging("LIFECOUNT: $npcuser_stat->{lifecount}");
                           $npcuser_stat->{lifecount}--;
                           if ( $npcuser_stat->{lifecount} <= 0 ) {
                             Loging("時間切れで終了...");

                             my @list = @$run_gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $npcuser_stat->{userid}){
                                     $timelinecoll->delete_many({"userid" => "$npcuser_stat->{userid}"}); # mognodb3.2
                                     splice(@$run_gacclist,$i,1);
                                 } 
                             } # for

                             # redisへの更新
                             my $run_json = to_json($run_gacclist);
                             $redis->set("GACC$ghostmanid" => $run_json);
                             $redis->expire("GACC$ghostmanid" => 32 ); #32秒保持する

                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit; 
                                 }
                             undef @list;
                             undef $run_json;
                             next; # foreach $npcuser_stat
                             }

           # mongo3.2用 3000m以内のデータを返す
           my $geo_points_cursole = $timelinecoll->query({ geometry => {
                                                           '$nearSphere' => {
                                                           '$geometry' => {
                                                            type => "point",
                                                                "coordinates" => [ $npcuser_stat->{loc}->{lng} , $npcuser_stat->{loc}->{lat} ]},
                                                           '$minDistance' => 0,
                                                           '$maxDistance' => 3000
                                     }}});
           @pointlist = $geo_points_cursole->all; # 原則重複無しの想定

           #makerをredisから抽出して、距離を算出してリストに加える。
             my $makerkeylist = $redis->keys("Maker*");
             my @makerlist = ();

             foreach my $aline (@$makerkeylist) {
                       my $makerpoint = from_json($redis->get($aline));

                      # radianに変換
                      my @s_p = NESW($npcuser_stat->{loc}->{lng}, $npcuser_stat->{loc}->{lat});
                      my @t_p = NESW($makerpoint->{loc}->{lng}, $makerpoint->{loc}->{lat});
                      my $t_dist = great_circle_distance(@s_p,@t_p,6378140);

                      if ( $t_dist < 3000) {
                       push (@makerlist, $makerpoint );
                       }
                      undef $makerpoint;
                      undef @s_p;
                      undef @t_p;
                      undef $t_dist;
                   }
               undef $makerkeylist;

               # makerとメンバーリストを結合する
               push (@pointlist,@makerlist);

               undef @makerlist;

            #   my $hash = { 'pointlist' => \@pointlist }; #受信した時と同じ状況

               # trapevent処理
               # trapeventのヒット判定
               my $trapmember_cursole = $trapmemberlist->query({ location => {
                                                           '$nearSphere' => {
                                                           '$geometry' => {
                                                            type => "point",
                                                                "coordinates" => [ $npcuser_stat->{loc}->{lng} , $npcuser_stat->{loc}->{lat} ]},
                                                           '$minDistance' => 0,
                                                           '$maxDistance' => 1
                                     }}});

               my @trapevents = $trapmember_cursole->all;

          #     my $debug = to_json(@trapevents);
          #     Loging("DEBUG: trapevents: $debug");
          #     undef $debug;

               if ( $#trapevents != -1 ){
                   Loging("DEBUG: TRAP on Event!!!!!!!");

                       #Chat表示 トラップ発動時に表示する
                       #日付設定 重複記述あり
                       my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                       # TTLレコードを追加する。
                   #    my $ttl = DateTime->now();

                   #    $chatobj = { geometry => $npcuser_stat->{geometry},
                   #                         loc => $npcuser_stat->{loc},
                   #                    icon_url => $npcuser_stat->{icon_url},
                   #                    username => $username,
                   #                         hms => $dt->hms,
                   #                        chat => $trapevents[0]->{message},
                   #                         ttl => $ttl,
                   #                  };

                        $chatobj->{geometry} = clone($npcuser_stat->{geometry});
                        $chatobj->{loc} = $npcuser_stat->{loc};
                        $chatobj->{icon_url} = $npcuser_stat->{icon_url};
                        $chatobj->{username} = $npcuser_stat->{name};
                        $chatobj->{hms} = $dt->hms;
                        $chatobj->{chat} = clone($trapevents[0]->{message});
                        $chatobj->{ttl} = DateTime->now();

                        # walkchatへの書き込み
                        $walkchatcoll->insert_one($chatobj);
                        Loging("DEBUG: $username insert chat");

                        my $chatjson = to_json($chatobj);

                        # 書き込み通知
                        $redis->publish( $chatname , $chatjson );
                        $redis->expire( $chatname => 3600 );
                     #   Loging("DEBUG: $username publish WALKCHAT");
                        undef $chatjson;

                   for my $i (@trapevents){
                     #  my $debug = to_json($i);
                     # delete trapevent
                     #  Loging("DEBUG: drop: $debug");
                       $trapmemberlist->delete_one({ '_id' => $i->{_id}});
                   }
                   undef @trapevents;
                   undef $trapmember_cursole;

                   # MemberTimeLineからの削除
                   $timelinecoll->delete_many({"userid" => "$npcuser_stat->{userid}"}); # mognodb3.2

                   # NPCアカウントの終了処理
                             my @list = @$run_gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $npcuser_stat->{userid}){
                                  splice(@$run_gacclist,$i,1);
                                 }
                             }
                             # redisへの更新
                             my $run_json = to_json($run_gacclist);
                             $redis->set("GACC$ghostmanid" => $run_json);
                             $redis->expire("GACC$ghostmanid" => 32 ); #32秒保持する

                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit;
                                 }
                             undef @list;
                             undef $run_json;
                             undef $dt;
                        #     undef $ttl;
                             next;
               } # if trapevents


      #   Loging("DB responce! $npcuser_stat->{status}");
          #  $pointlist = $hash->{pointlist};
            $pointlist = \@pointlist;
            weaken($pointlist);
            $targetlist = $pointlist;

          #  undef $hash;

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
              writejson($npcuser_stat);
              last;
              } # if
        }

undef $geo_points_cursole;


             # テスト用　位置保持
             if ( $npcuser_stat->{status} eq "STAY") {
                 $npcuser_stat->{icon_url} = iconchg($npcuser_stat->{status});
                 writejson($npcuser_stat);

                 $txtmsg = "STAY desuyo!";
                 $chatobj->{chat} = $txtmsg;
                 writechatobj($npcuser_stat);
                 undef $txtmsg;
                 next; 
                }

             my $runway_dir;

             # ランダム移動処理
             if ( $npcuser_stat->{status} eq "random" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$targetlist){
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                         next;
                         }
                         push(@$targets,$i);
                     }

                my @chk_targets = @$targets;
                Loging("DEBUG: random chk_targets: $#chk_targets");

                # 初期方向
                $runway_dir = 1 if (! defined $runway_dir);

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

                   if (int(rand(10)) > 8) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "chase";
                        Loging("Mode change Chase!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "追跡モードになったよ！";
                        $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                      #  writechatobj($npcuser_stat);
                        next;
                   } elsif (int(rand(10)) > 6 ) {

                   ####     if ($#chk_targets == -1) { next; } #pass  searchではtargetは不要

                        $npcuser_stat->{status} = "search";
                        Loging("Mode change Search!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "検索モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                      #  writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
                   } elsif (int(rand(10)) > 6 ) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "round";
                        Loging("Mode change Round!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "周回モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
                   } elsif (int(rand(10)) > 8 ) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "逃走モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
                    }

                #スタート地点からの距離判定
                # radianに変換
                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($s_lng, $s_lat);
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                undef @s_p;
                undef @t_p;

                Loging("mode Random: $t_dist");

                spnchange($t_dist);

                # スタート地点から2km離れて、他に稼働するものがあれば、
                if ($t_dist > 2000 ){

                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$targetlist){
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                         next;
                         }
                         push(@$targets,$i);
                     }

                     my @t_list = @$targets;
                     if ( $#t_list > 2 ){
                        $npcuser_stat->{status} = "chase";
                        Loging("Mode change Chase!");
                        my $txtmsg  = "追跡モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef @t_list;
                        next;
                        }
                     undef @t_list;
                }  # t_dist > 2000 

              if (($npcuser_stat->{status} eq "random" ) && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
                  }


              writejson($npcuser_stat);
              undef @chk_targets; 
              next;
             } # if stat random

    # 追跡モード
      my $target = $npcuser_stat->{target};  # targetのUIDが入る クリアされるまで固定
      my $t_obj;   # targetのステータス 毎度更新される
         @$targets = (); #targetlistからの入れ替え用
             #自分をリストから除外する
             for my $i (@$targetlist){
                 if ( $i->{userid} eq $npcuser_stat->{userid}){
                     next;
                     }
                     push(@$targets,$i);
                 }

       if ( $npcuser_stat->{status} eq "chase" ){

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Chase Targets $#chk_targets ");

             if (($target eq "")&&($#chk_targets > 0)) {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;
                }

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合 random-mode
              if ( $t_obj->{name} eq "" ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = ""; 
                 $npcuser_stat->{target} = ""; 
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;

                 next;
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: ======== $deb_obj ========"); 
              undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

           #   Loging("DEBUG: lat: $lat lng: $lng");
           #   Loging("DEBUG: t_lat: $t_lat t_lng: $t_lng");


              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);
                 $rundirect = $t_direct;
              undef @s_p;
              undef @t_p;

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
                        $lng = overArealng($lng);
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

              # 5m以下に近づくとモードを変更
              if ($t_dist < 5 ) {
                 $npcuser_stat->{status} = "round"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........round.");
                 my $txtmsg  = "roundモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 }


              if (($npcuser_stat->{status} eq "chase" ) && ( $#chk_targets > 20 )) {

                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                  }


              writejson($npcuser_stat);

              undef $target;
              undef $t_obj;
              undef $t_dist;
              undef $t_direct;
              undef @chk_targets; 
              next;
             } # if chase

       # 逃走モード
       if ( $npcuser_stat->{status} eq "runaway" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$targetlist){
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                         next;
                         }
                         push(@$targets,$i);
                     }

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: runaway Targets $#chk_targets ");

             if (($target eq "")&&($#chk_targets != -1)) {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("RUNAWAY target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;
                }

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、randomモードへ
              if (( $t_obj->{name} eq "" )||(! defined $t_obj->{name} )) {
                 $npcuser_stat->{status} = "random"; 
                 $target = ""; 
                 $npcuser_stat->{target} = ""; 
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 next;
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: RUNAWAY ======== $deb_obj ========"); 
              undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

           #   Loging("DEBUG: RUNAWAY: lat: $lat lng: $lng");
           #   Loging("DEBUG: RUNAWAY: t_lat: $t_lat t_lng: $t_lng");

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);
              undef @s_p;
              undef @t_p;

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
                        $lat = $lat + rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn + 0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + 0.001);
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
              if (($#chk_targets < 20) && (int(rand(10) > 7))) {
                        $npcuser_stat->{status} = "round";
                        Loging("Mode change Round!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "周回モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;

              # 3000m以上に離れるとモードを変更
              } elsif (($t_dist > 3000 ) && ($#chk_targets > 20)) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 }

              writejson($npcuser_stat);

              undef $target;
              undef $t_obj;
              undef @chk_targets;
              undef $t_dist;
              undef $t_direct;
              next;
          } # runaway

       # 周回動作
       if ( $npcuser_stat->{status} eq "round" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$targetlist){
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                         next;
                         }
                         push(@$targets,$i);
                     }

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: round Targets $#chk_targets ");

             if ($target eq "") {
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("ROUND target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;
                }
             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
              # ターゲットをロストした場合、randomモードへ
              if ( $t_obj->{name} eq "" ) {
                 $npcuser_stat->{status} = "random";
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: ROUND ======== $deb_obj ========"); 
              undef $deb_obj;

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

           #   Loging("DEBUG: ROUND: lat: $lat lng: $lng");
           #   Loging("DEBUG: ROUND: t_lat: $t_lat t_lng: $t_lng");

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($t_lng, $t_lat);
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $t_lat, $t_lng);
              undef @s_p;
              undef @t_p;

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
                        $lat = $lat + rand($point_spn+0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn+0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn+0.001);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn+0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn+0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn+0.001);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn+0.001);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn+0.001);
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
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 } 

              if (($npcuser_stat->{status} eq "round") && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                }


              writejson($npcuser_stat);

              undef $target;
              undef $t_obj;
              undef @chk_targets; 
              undef $t_dist;
              undef $t_direct;
              next;

          } # round

             # 検索モード
             if ( $npcuser_stat->{status} eq "search" ){

                #周囲にユニットが在るか確認
                     @$targets = ();
                     #自分をリストから除外する
                     for my $i (@$targetlist){
                         if ( $i->{userid} eq $npcuser_stat->{userid}){
                         next;
                         }
                         push(@$targets,$i);
                     }

                my @chk_targets = @$targets;
                Loging("DEBUG: random chk_targets: $#chk_targets");

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
                               writejson($npcuser_stat);
                               undef $resjson;
                               next;
                       }
                    my $list = $resjson->{results};
                    weaken($list);
                    my @spointlist = @$list;
                    my $slice = int(rand($#spointlist));
                    Loging("slice: $slice");
                    my $deb = to_json($spointlist[$slice]);
                    Loging("DEBUG: slice: $deb");
                    undef $deb;
                    undef $slice;

                    $npcuser_stat->{place}->{lat} = $spointlist[$slice]->{geometry}->{location}->{lat} + 0;
                    $npcuser_stat->{place}->{lng} = $spointlist[$slice]->{geometry}->{location}->{lng} + 0;
                    $npcuser_stat->{place}->{name} = $spointlist[$slice]->{name};

                    my $txtmsg = "今から$npcuser_stat->{place}->{name}へ行くよ！";
                       $txtmsg = encode_utf8($txtmsg);
                    $chatobj->{chat} = $txtmsg;
                    writechatobj($npcuser_stat);
                    undef $txtmsg;

                    Loging("DEBUG: Place: $npcuser_stat->{place}->{name} $npcuser_stat->{place}->{lat} $npcuser_stat->{place}->{lng}");

                    undef $list;
                    undef @spointlist;
                    undef $slice;
                    undef $resjson;

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

                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($npcuser_stat->{place}->{lng}, $npcuser_stat->{place}->{lat});
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                Loging("DEBUG: dist: $t_dist");
                undef @s_p;
                undef @t_p;

                spnchange($t_dist);

               if ( $t_dist < 5 ) {
                   $point_spn = 0.0002;  #元に戻す
                   $npcuser_stat->{point_spn} = 0.0002;
                   $npcuser_stat->{status} = "random";
                   $npcuser_stat->{place}->{name} = "";
                   $npcuser_stat->{place}->{lat} = "";
                   $npcuser_stat->{place}->{lng} = "";
                   Loging("Mode change random!");
                   writejson($npcuser_stat);

                   $txtmsg = "Randomモードに変わったよ！";
                   $txtmsg = encode_utf8($txtmsg);
                   $chatobj->{chat} = $txtmsg;
                #   writechatobj($npcuser_stat);
                   undef $txtmsg;
               }

              if (($npcuser_stat->{status} eq "search" ) && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
                  }

              writejson($npcuser_stat);
              next;
             } # search

      } #foreach $run_gacclist
      # 以上は10秒毎に実行されるアカウントループ

             my $run_json = to_json($run_gacclist);
                $redis->set("GACC$ghostmanid" => $run_json);
                $redis->expire("GACC$ghostmanid" => 32 ); #32秒保持する
                undef $run_json;


#   my  $psize = total_size(\%main::);
#   Loging("main: $psize");
#     $psize = total_size(\%Loging::);
#   Loging("Loging: $psize");
#     $psize = total_size(\%get_gacclist::);
#   Loging("get_gacclist: $psize");
#     $psize = total_size(\%npcinit::);
#   Loging("npcinit: $psize");
#     $psize = total_size(\%iconchg::);
#   Loging("iconchg: $psize");
#     $psize = total_size(\%geoarea::);
#   Loging("geoarea: $psize");
#     $psize = total_size(\%overArealat::);
#   Loging("overArealat: $psize");
#     $psize = total_size(\%overArealng::);
#   Loging("overArealng: $psize");
#     $psize = total_size(\%spnchange::);
#   Loging("spnchange: $psize");
#     $psize = total_size(\%geoDirect::);
#   Loging("geoDirect: $psize");
#     $psize = total_size(\%writejson::);
#   Loging("writejson: $psize");
#     $psize = total_size(\%writechatobj::);
#   Loging("writechatobj: $psize");
#   my   $psize = total_size($run_gacclist);
#   Loging("###### run_gacclist: $psize");
#   my   $psize = total_size($ua);
#   Loging("###### ua: $psize");
#    Dump(\%main::);
#Loging("-----find-----");
#find_cycle($timelinecoll);
#find_cycle($timelinelog);

#Loging("run_gacclist check");
#Dump($run_gacclist);
#print Dumper($run_gacclist);
#Loging("run_gacclist find_cycle");
#find_cycle($run_gacclist);

#Loging("-----run_gacclist-----");
#print Dumper($run_gacclist);
#Loging("-----chatobj-----");
#print Dumper($chatobj);
#Loging("-----username-----");
#print Dumper($username);

#Loging("gacclist check");
#Dump($gacclist);
Loging("run_gacclist check");
Dump($run_gacclist);
#Loging("chatobj check");
#Dump($chatobj);
#Loging("username check");
#Dump($username);
#Loging("rundirect check");
#Dump($rundirect);

        Loging("---------------------LOOP END-----------------------------------");

       $cv->send;
       });  # AnyEvent CV or Mojo::IOLoop
    $cv->recv;

     # 以下redisイベント受信時の処理
     #redis receve
     $redis->on(message => sub {
                  my ($redis,$mess,$channel) = @_;
                      Loging("DEBUG: on channel: $mess");

                      if ( $channel ne $attackCH ) { 
                                          undef $mess;
                                          return;
                         } # filter channel

                      my $messobj = from_json($mess);

                      if ( defined $messobj->{chat} ) { return; }  # chatはパスする

                      my $dropacc;

                      #実行時点でのアカウントが不明なので、受信時にアカウントを一通りチェックする必要がある。
                      foreach my $acc (@$run_gacclist){
                          if ( $messobj->{to} eq $acc->{userid} ){
                              $dropacc = clone($acc);
                              last;
                          }
                      }
                      # 担当していないアカウントの場合パスする。
                      if (! defined $dropacc){
                         Loging("Not Domain account...pass $messobj->{execemail}");
                         undef $messobj;
                         return; 
                         }
                                Loging("DEBUG: redis acc loop: $dropacc->{name}");

                              # toが重複するケースが在るので先にrun_gacclistから除外をしないと回数が増える。。。
                                my @list = @$run_gacclist;
                                for (my $i=0; $i <= $#list ; $i++){
                                    if ( $list[$i]->{userid} eq $messobj->{to}){
                                     splice(@$run_gacclist,$i,1);
                                     Loging("DROP ACC $list[$i]->{name} ");
                                     last;
                                    } 
                                }

                                # redisへの更新
                                my $run_json = to_json($run_gacclist);
                                $redis->set("GACC$ghostmanid" => $run_json);
                                $redis->expire("GACC$ghostmanid" => 32 ); #32秒保持する
                                undef $run_json;
                                undef @list;

                       # 元々はhitnameをsite1に送るが、db直結になりアカウント情報を持つのでhitnameを利用しない
                                Loging("$username 祓われた。。。");
                                $timelinecoll->delete_many({"userid" => "$messobj->{to}"}); # mognodb3.2

                                # 履歴を読んでカウントアップする
                                my $memcountobj = $membercount->find_one_and_delete({'userid'=>"$messobj->{execute}"});
                                my $pcnt = 0;
                                   $pcnt = $memcountobj->{count} if ($memcountobj ne 'null');
                                   $pcnt = ++$pcnt;
                                   $memcountobj->{count} = $pcnt;
                                   $memcountobj->{userid} = $messobj->{execute};
                                   delete $memcountobj->{_id};

                            #    Loging("DEBUG: $pcnt : $messobj->{execute} | $messobj->{to} | $dropacc->{name} ");

                                   $membercount->insert_one($memcountobj);

                                #ランキング処理
                                $redis->zadd('gscore', "$pcnt", "$messobj->{execemail}");

                                my $txtmsg = "そして$dropacc->{name} は祓われた！";
                                   $txtmsg = encode_utf8($txtmsg);
                                $chatobj->{chat} = $txtmsg;
                                writechatobj($dropacc);

                                undef $txtmsg;
                                undef $dropacc;
                                undef $pcnt;
                                undef $messobj;
                                undef $mess;
                                undef $memcountobj;
                  });  # redis on message

} #while  AnyEvnt  

#   }); #loop 
#   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

