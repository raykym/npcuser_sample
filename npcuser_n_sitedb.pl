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
use Mojo::IOLoop::Delay;
use MongoDB;
use Mojo::Redis2;
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;

$| = 1;

# DB設定
my $mongoclient = MongoDB->connect('mongodb://dbs-1:27017');

my $redis ||= Mojo::Redis2->new(url => 'redis://dbs-1:6379');

my $wwdb = $mongoclient->get_database('WalkWorld');
my $timelinecoll = $wwdb->get_collection('MemberTimeLine');

my $wwlogdb = $mongoclient->get_database('WalkWorldLOG');
my $timelinelog = $wwlogdb->get_collection('MemberTimeLinelog');

# WalkChat用
my $holldb = $mongoclient->get_database('holl_tl');
my $walkchatcoll = $holldb->get_collection('walkchat');

my $chatname = 'WALKCHAT';
my @chatArray = ( $chatname );

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

my $ghostmanid = "$ARGV[0]";
   if ( !defined $ghostmanid ) {
        Loging("UNDEFINED ghostmanid!!!!!!!");
        exit;
       }

my $username = "";
my $userid = "";

# 表示用ログフォーマット
sub Loging{
    my $logline = shift;
    my $dt = DateTime->now();

    say "$dt | $username: $logline";
    return;
}

my $gacclist;

get_gacclist();

my $nullcount = 0;

sub get_gacclist{
# リストの取得
    #redis経由に変更した為、直接取得する
    $gacclist = $redis->get("GACC$ghostmanid");
    if ( defined $gacclist) {
        $gacclist = from_json($gacclist);
        } else {
               $gacclist = [];
               }
   # my @list = @$gacclist;
   #    Loging("gacclist: $#list +1");
}

# 初期値
my $lat = 35.677543 + rand(0.001) - (0.001/2);
my $lng = 139.9055707 + rand(0.001) - (0.001/2);
my $s_lat = $lat;
my $s_lng = $lng;
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

# $gacclistと実行中のリストの分岐、 アカウントの削除は自前で追加のみチェックする
   my $run_gacclist =[];
   # 差分が在れば追加
   foreach my $acc (@$gacclist){
               push(@$run_gacclist,$acc) unless grep { $_->{name} =~ $acc->{name} } @$run_gacclist;
           }
 #  my $debug = to_json($run_gacclist);
 #  Loging("run_gacclist: $debug");
 #  undef $debug;

   npcinit();

sub npcinit {
# パラメータの初期化 
    for my $acc (@$run_gacclist){
        $acc->{status} = "random" if ( $acc->{status} eq "");
        $acc->{geometry}->{coordinates} = [ $lng , $lat ] if ( $acc->{geometry}->{coordinates} == [0,0] );
        $acc->{loc}->{lat} = $lat if ( $acc->{loc}->{lat} == 0);
        $acc->{loc}->{lng} = $lng if ( $acc->{loc}->{lng} == 0);
        $acc->{rundirect} = int(rand(360)) if ( $acc->{rundirect} eq "");
        $acc->{point_spn} = 0.0002 if ( $acc->{point_spn} eq "");
        $acc->{lifecount} = 60480 if ( $acc->{lifecount} eq "");
        $acc->{icon_url} = iconchg($acc->{status});

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
          return $icon_url;
        } elsif ( $runmode eq "chase"){ 
          my $icon_url =  "/img/ghost4_32px.png";
      #    Loging("iconchg: $icon_url");
          return $icon_url;
        } elsif ( $runmode eq "runaway" ){
          my $icon_url = "/img/ghost3_32px.png";
      #    Loging("iconchg: $icon_url");
          return $icon_url;
        } elsif ( $runmode eq "round" ){
          my $icon_url = "/img/ghost1_32px.png";
      #    Loging("iconchg: $icon_url");
          return $icon_url;
        } elsif ( $runmode eq "STAY"){ 
          my $icon_url = "/img/ghost2_32px.png";
      #    Loging("iconchg: $icon_url");
          return $icon_url;
        } elsif ( $runmode eq "search"){
          my $icon_url = "/img/ghost4_32px.png";
      #    Loging("iconchg: $icon_url");
          return $icon_url;
        }
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
           #    Loging("point_spn: $point_spn");
             } else {
               $point_spn = 0.0001;
           #    Loging("point_spn: $point_spn");
             }
}

my $pointlist;
my $targetlist;
my $targets = [];
my $oncerun = "true";


# 初回マーク処理
    foreach my $npcuser_stat (@$run_gacclist){
                  my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
                  # TTLレコードを追加する。
                  my $ttl = DateTime->now();
                  $username = $npcuser_stat->{name};
                  $npcuser_stat->{ttl} = $ttl;
                  $timelinecoll->delete_many({"userid" => $npcuser_stat->{userid}}); # mognodb3.2 削除してから
                  $timelinecoll->insert_one($npcuser_stat);
                  $timelinelog->insert_one($npcuser_stat);
    } # foreach $npcuser_stat


#ループ処理 
    Mojo::IOLoop->recurring(
                     10 => sub {
                           my $loop = shift;

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
                             $redis->expire("GACC$ghostmanid" => 12 ); #12秒保持する
                             undef $run_json;

                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit; 
                                 }
                             undef @list;
                             next; # foreach $necuser_stat
                             }

           # 攻撃を受けたか確認する　基本NPC用
           my $attack_chk = $timelinecoll->find_one({ "to" => $userid });
           Loging("DEBUG: $attack_chk->{execute} | $attack_chk->{execemail} | $attack_chk->{icon_url} ");

           # mongo3.2用 3000m以内のデータを返す
           my $geo_points_cursole = $timelinecoll->query({ geometry => {
                                                           '$nearSphere' => {
                                                           '$geometry' => {
                                                            type => "point",
                                                                "coordinates" => [ $npcuser_stat->{loc}->{lng} , $npcuser_stat->{loc}->{lat} ]},
                                                           '$minDistance' => 0,
                                                           '$maxDistance' => 3000
                                     }}});
           my @pointlist = $geo_points_cursole->all; # 原則重複無しの想定

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
                   }

               # makerとメンバーリストを結合する
                 push @pointlist,@makerlist;

               my $hash = { 'pointlist' => \@pointlist }; #受信した時と同じ状況


            # 終了判定
            if ( defined $attack_chk->{to} ){
                if ( $attack_chk->{to} eq $userid ) {

                    my $delay = Mojo::IOLoop::Delay->new;
                       $delay->steps(

                       sub {
                        my $delay = shift;
                            Loging("$username 祓われた。。。");
                            my $datenow = DateTime->now();
                            my $hitparam = { to => $attack_chk->{to}, execute => $attack_chk->{execute}, hitname => $username, ttl => $datenow, execemail => $attack_chk->{execemail} };
                            $timelinelog->insert_one($hitparam);
                            $timelinecoll->delete_many({"userid" => "$attack_chk->{to}"}); # mognodb3.2
                            undef $datenow;

                            # 1sec waitさせる 上記の書き込みは本来web経由だが、直接書き込み処理の為、waitを入れる
                            Mojo::IOLoop->timer(1 => $delay->begin);

                            #撃墜結果を集計
                                          #NPCが接続した状態で、executeしたuidのデータを作成する。
                            my $executelist = $timelinelog->find({ 'execute' => $attack_chk->{execute}, 'hitname' => {'$exists' => 1} });

                            my @execute = $executelist->all;
                            my $pcnt = $#execute + 1;

                            $redis->set( "GHOSTGET$attack_chk->{execute}" => $pcnt );

                            #ランキング処理
                            #攻撃シグナルにexecemailを追加して、emailでsidを検索出来るように修正した。
                            $redis->zadd('gscore', "$pcnt", "$attack_chk->{execemail}");

                            my $txtmsg = "そして$npcuser_stat->{name} は祓われた！";
                            $chatobj->{chat} = $txtmsg;
                            writechatobj($npcuser_stat);

                            undef @execute;
                            undef $pcnt;
                       },
                       sub {
                        my ($delay,@param) = @_;
                             my @list = @$run_gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $attack_chk->{to}){
                                  splice(@$run_gacclist,$i,1);
                                 } 
                             }
                             # redisへの更新
                             my $run_json = to_json($run_gacclist);
                             $redis->set("GACC$ghostmanid" => $run_json);
                             $redis->expire("GACC$ghostmanid" => 12 ); #12秒保持する
                             undef $run_json;

                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit; 
                                 }
                             undef @list;
                             next;
                       })->wait;

               } else { next; } # 自分のUIDでなければパスする。
             } #if defined to

      # デバッグ
      #   Loging("---------------TOP");
      #   my $dumphash = Dumper($hash);
      #   Loging("DumperHash: $dumphash");
      #   Loging("---------------END");

      #   Loging("DB responce! $npcuser_stat->{status}");
            $pointlist = $hash->{pointlist};
            $targetlist = clone($pointlist);

     # デバッグ用
     #    Loging("---------------TOP");
     #    for my $linejson (@$pointlist) { 
     #      my $i = to_json($linejson);
     #      Loging("$i");
     #    }
     #    Loging("---------------END");

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

   ### #元on jsonの終わり

             # テスト用　位置保持
             if ( $npcuser_stat->{status} eq "STAY") {
                 $npcuser_stat->{icon_url} = iconchg($npcuser_stat->{status});
                 writejson($npcuser_stat);

                 $txtmsg = "STAY desuyo!";
                 $chatobj->{chat} = $txtmsg;
                 writechatobj($npcuser_stat);
                 next; #return
                }


             my $runway_dir;

             # ランダム移動処理
             if ( $npcuser_stat->{status} eq "random" ){

                #周囲にユニットが在るか確認
                     $targets = [];
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
                        $chatobj->{chat} = $txtmsg;
                      #  writechatobj($npcuser_stat);
                        next;
                   } elsif (int(rand(10)) > 6 ) {

                   ####     if ($#chk_targets == -1) { next; } #pass  searchではtargetは不要

                        $npcuser_stat->{status} = "search";
                        Loging("Mode change Search!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "検索モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                   } elsif (int(rand(10)) > 6 ) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "round";
                        Loging("Mode change Round!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "周回モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                   } elsif (int(rand(10)) > 8 ) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                    }

                #スタート地点からの距離判定
                # radianに変換
                sub NESW { deg2rad($_[0]), deg2rad(90 - $_[1]) }
                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($s_lng, $s_lat);
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);

                Loging("mode Random: $t_dist");

                spnchange($t_dist);

                @chk_targets = @$targets;
                Loging("DEBUG: Targets $#chk_targets ");

                # スタート地点から2km離れて、他に稼働するものがあれば、
                if ($t_dist > 2000 ){

                     $targets = [];
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
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                        }
                }  # t_dist > 2000 

              if (($npcuser_stat->{status} eq "random" ) && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                  }

             #   undef @chk_targets; # clear

              writejson($npcuser_stat);
              next;
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
sub writejson {
    my $npcuser_stat = shift;
                  $timelinecoll->delete_many({"userid" => $npcuser_stat->{userid}}); # mognodb3.2 削除してから
             #    $timerecord = DateTime->now()->epoch();
             #    $timerecord = $timerecord * 1000; #ミリ秒に合わせるために
             #    $npcuser_stat->{time} = $timerecord;
                 $npcuser_stat->{ttl} = DateTime->now();

                  $npcuser_stat->{geometry}->{coordinates}= [ $lng, $lat ];
                  $npcuser_stat->{loc}->{lat} = $lat;
                  $npcuser_stat->{loc}->{lng} = $lng; 
                  $npcuser_stat->{point_spn} = $point_spn;
                  $npcuser_stat->{rundirect} = $rundirect;
                  $npcuser_stat->{icon_url} = iconchg($npcuser_stat->{status});

             my $debmsg = to_json($npcuser_stat);
                 Loging("WRITE MONGODB: $debmsg");
                 $timelinecoll->insert_one($npcuser_stat);
                 $timelinelog->insert_one($npcuser_stat);

         #個別の更新で書き込んでおかないとダメな場合もあるか。。。？
         #    my $run_json = to_json($run_gacclist);
         #       $redis->set("GACC$ghostmanid" => $run_json);
         #       $redis->expire("GACC$ghostmanid" => 12 ); #12秒保持する
         #       undef $run_json;

                 return;
}

# chat用　送信
sub writechatobj {
    my $npcuser_stat = shift;
               my $dt = DateTime->now( time_zone => 'Asia/Tokyo');
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

                  return;
}

    # 追跡モード
      my $target = $npcuser_stat->{target};  # targetのUIDが入る クリアされるまで固定
      my $t_obj;   # targetのステータス 毎度更新される
         $targets = []; #targetlistからの入れ替え用
             #自分をリストから除外する
             for my $i (@$targetlist){
                 if ( $i->{userid} eq $npcuser_stat->{userid}){
                     next;
                     }
                     push(@$targets,$i);
                 }

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: Chase Targets $#chk_targets ");

       if ( $npcuser_stat->{status} eq "chase" ){

             if (($target eq "")&&($#chk_targets > 0)) {
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
               
              # ターゲットをロストした場合 random-mode
              if ( $t_obj->{name} eq "" ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = ""; 
                 $npcuser_stat->{target} = ""; 
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
               #  writechatobj($npcuser_stat);

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
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 }


              if (($npcuser_stat->{status} eq "chase" ) && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                  }

         #    undef @chk_targets; # clear

              writejson($npcuser_stat);
              next;
             } # if chase

       # 逃走モード
       if ( $npcuser_stat->{status} eq "runaway" ){

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
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 next; # return
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: RUNAWAY ======== $deb_obj ========"); 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

           #   Loging("DEBUG: RUNAWAY: lat: $lat lng: $lng");
           #   Loging("DEBUG: RUNAWAY: t_lat: $t_lat t_lng: $t_lng");

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
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);

              # 1500m以上に離れるとモードを変更
              } elsif (($t_dist > 1500 ) || ($#chk_targets > 20)) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 }

          #   undef @chk_targets; # clear

              writejson($npcuser_stat);
              next;
          } # runaway

       # 周回動作
       if ( $npcuser_stat->{status} eq "round" ){

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
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 }

              my $deb_obj = to_json($t_obj); 
              Loging("DEBUG: ROUND ======== $deb_obj ========"); 

              my $t_lat = $t_obj->{loc}->{lat};
              my $t_lng = $t_obj->{loc}->{lng};

           #   Loging("DEBUG: ROUND: lat: $lat lng: $lng");
           #   Loging("DEBUG: ROUND: t_lat: $t_lat t_lng: $t_lng");

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
                 $chatobj->{chat} = $txtmsg;
               #  writechatobj($npcuser_stat);
                 } 

              if (($npcuser_stat->{status} eq "round") && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                     #   return;
                }

        #     undef @chk_targets; # clear

              writejson($npcuser_stat);
              next;

          } # round

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
                               writejson($npcuser_stat);
                               next;
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
                    writechatobj($npcuser_stat);

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

                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($npcuser_stat->{place}->{lng}, $npcuser_stat->{place}->{lat});
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                Loging("DEBUG: dist: $t_dist");

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
                   $chatobj->{chat} = $txtmsg;
                 #  writechatobj($npcuser_stat);

               }

              if (($npcuser_stat->{status} eq "search" ) && ( $#chk_targets > 20 )) {
                 # runawayモードへ変更
                        $npcuser_stat->{status} = "runaway";
                        Loging("Mode change Runaway!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "逃走モードになったよ！";
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        next;
                  }

              writejson($npcuser_stat);
              next;
             } # search

      } #foreach $run_gacclist

             my $run_json = to_json($run_gacclist);
                $redis->set("GACC$ghostmanid" => $run_json);
                $redis->expire("GACC$ghostmanid" => 12 ); #12秒保持する
                undef $run_json;

        Loging("---------------------LOOP END-----------------------------------");
   }); #loop 

   Mojo::IOLoop->start unless Mojo::IOLoop->is_running;

