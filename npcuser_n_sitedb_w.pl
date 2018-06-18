#!/usr/bin/env perl

# westwind用ヴァージョン
# site1を経由せずDBへ直接書き込みバージョン
# アカウント情報はredisから受け取り、個々の処理を行って、mongodb、redisへ位置情報を書き戻す
# 終了処理も此処で行い、mongodbとredisへ送信する
# 起動時に引数でsidを受け取る。
# Mojo::Redis2のメモリーリークが問題なので、Redis、AnyEvent::Redisに置き換え
#
# 緯度経度の限界処理追加
# usage
# npcuser_n_sitedb.pl [ghostmanid]

my $timelineredis = 0; # 0: mongodb  1: redis

my $mongoserver = "10.140.0.8";
my $redisserver = "10.140.0.8";
my $server = "westwind.backbone.site";   # DNS lookup ghostman access

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
#use Mango;
#use Mojo::Redis2;
use Encode qw(encode_utf8 decode_utf8);
#use Data::Dumper;
#use Devel::Size qw/total_size/;
#use Devel::Cycle;
use Scalar::Util qw(weaken);
#use Devel::Peek;
use EV;
use AnyEvent;
#use Redis;
use AnyEvent::Redis;

use lib '/home/debian/perlwork/mojowork/server/ghostman/lib/Ghostman/Model';
use Sessionid;

$| = 1;


# DB設定
my $mongoclient = MongoDB->connect("mongodb://$mongoserver:27017");
#my $mango = Mango->new('mongodb://dbs-1:27017'); 

#一般コマンド用
my $redis = AnyEvent::Redis->new(
    host => "$redisserver",
    port => 6379,
    encoding => 'utf8',
    on_error => sub { warn @_ },
    on_cleanup => sub { warn "Connection closed: @_" },
);

#subscribe用
my $redisAE = AnyEvent::Redis->new(
    host => "$redisserver",
    port => 6379,
    encoding => 'utf8',
  #  on_error => sub { warn @_ },
    on_error => sub { die "error on redis"; },
  #  on_cleanup => sub { warn "Connection closed: @_" },
    on_cleanup => sub { die "error redis cleanup"; },
);

my $wwdb = $mongoclient->get_database('WalkWorld');
my $timelinecoll = $wwdb->get_collection('MemberTimeLine');
my $trapmemberlist = $wwdb->get_collection('trapmemberlist');

my $wwlogdb = $mongoclient->get_database('WalkWorldLOG');
my $timelinelog = $wwlogdb->get_collection('MemberTimeLinelog');
my $membercount = $wwlogdb->get_collection('MemberCount');
my $npcuserlog = $wwlogdb->get_collection('npcuserlog');

# WalkChat用
my $holldb = $mongoclient->get_database('holl_tl');
my $walkchatcoll = $holldb->get_collection('walkchat');

my $chatname = 'WALKCHAT';
my $attackCH = 'ATTACKCHN';
my @chatArray = ( $attackCH ); # chatは受信させない

# 用事と休憩に分類
my @keyword = ( [
                "コンビニ",
                "ファーストフード",
                "レストラン",
                "駅",
                "神社",
                "寺",
                "橋",
                "池",
                "沼",
                "公園",
                "道の駅",
                "遊園地",
                "牧場",
                ],
                [
                "図書館",
                "病院",
                "郵便局",
                "役所",
                ],
              );

my $apikey = "AIzaSyC8BavSYT3W-CNuEtMS5414s3zmtpJLPx8";
my $radi = 3000; #検索レンジ

my $ua = Mojo::UserAgent->new;
my $cookie_jar = $ua->cookie_jar;
   $ua = $ua->cookie_jar(Mojo::UserAgent::CookieJar->new);
   #$ua->max_connections(1);
   $ua->connect_timeout(5);
   $ua->inactivity_timeout(7);

my $username = "";
my $userid = "";

my $ghostmanid = "$ARGV[0]";
   if (( ! defined $ghostmanid )||($ghostmanid eq "")) {
        Loging("UNDEFINED ghostmanid!!!!!!!");
        exit;
       }

my $gacclist;
my $run_gacclist;
my @gacclist_on;

my $nullcount = 0;

# 初期値
my $lat = 35.677543 + rand(0.001) - (0.001/2);
my $lng = 139.9055707 + rand(0.001) - (0.001/2);
my $s_lat = $lat;
my $s_lng = $lng;
my $runmode = "random";

my $lifecount = 17280; # 2days/10sec    # npcinitで設定されている　　　60480; #1week /10sec count 初期設定で利用、その後gacclistで置き換えられる

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
my @makerlist = ();
my @makeracclist = ();


##### subs #####

# 表示用ログフォーマット
sub Loging{
    my $logline = shift;
       $logline = encode_utf8($logline);
    my $dt = DateTime->now();
    say "$dt | $username: $logline";
    $logline = decode_utf8($logline);
    my $dblog = { 'ttl' => $dt, 'logline' => $logline, 'ghostmanid' => $ghostmanid };
       $npcuserlog->insert_one($dblog);
    
    undef $logline;
    undef $dt;
    undef $dblog;

    return;
}

sub get_gacclist{    # AE移行で不要に、、、
# リストの取得
    #redis経由に変更した為、直接取得する lisner側でgacclistを勝手に受け取っているはず、、、
  #  @$gacclist = (); # AEの為　リークは？
  #  $gacclist = $redis->get("GACC$ghostmanid");
  #  if ( defined $gacclist) {
  #      $gacclist = from_json($gacclist);
  #      } else {
  #             @$gacclist = ();
  #             }
   # my @list = @$gacclist;
   #    Loging("gacclist: $#list +1");
}

sub npcinit {
# パラメータの初期化 
    for my $acc (@$run_gacclist){
        $acc->{status} = "random" if ( $acc->{status} eq "");
      #  $acc->{status} = "STAY" if ( $acc->{status} eq "");
        $acc->{geometry}->{coordinates} = [ $lng , $lat ] if ( $acc->{geometry}->{coordinates} == [0,0] );
        $acc->{loc}->{lat} = $lat if ( $acc->{loc}->{lat} == 0);
        $acc->{loc}->{lng} = $lng if ( $acc->{loc}->{lng} == 0);
        $acc->{rundirect} = int(rand(360)) if ( $acc->{rundirect} eq "");
        $acc->{point_spn} = 0.0003 if ( $acc->{point_spn} eq "");
      #  $acc->{lifecount} = 60480 if ( $acc->{lifecount} eq "");
        $acc->{lifecount} = 17280 if ( $acc->{lifecount} eq "");
        $acc->{icon_url} = iconchg($acc->{status}) if ($acc->{icon_url} eq "");
        $acc->{chasecnt} = 0 if ( ! defined $acc->{chasecnt} );

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
          if ( $t_dist > 30 ) {
               $point_spn = 0.0003;
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
                  $timelinecoll->delete_many({"userid" => $npcuser_stat->{userid}}) if $timelineredis == 0; # mognodb3.2 削除してから
                  $npcuser_stat->{ttl} = DateTime->now();

                  $npcuser_stat->{geometry}->{coordinates} = [ $lng, $lat ];
                  $npcuser_stat->{loc}->{lat} = $lat;
                  $npcuser_stat->{loc}->{lng} = $lng; 
                  $npcuser_stat->{point_spn} = $point_spn;
                  $npcuser_stat->{rundirect} = $rundirect;
                  $npcuser_stat->{icon_url} = iconchg($npcuser_stat->{status});

             my $debmsg = to_json($npcuser_stat);
                 Loging("DEBUG: WRITE MONGODB: $debmsg");

                 if ( $timelineredis == 0 ) {
                     $timelinecoll->insert_one($npcuser_stat);
                 } elsif ( $timelineredis == 1 ) {
                    my $npcuser_stat_json = to_json($npcuser_stat);
                    $redis->set("Maker$npcuser_stat->{userid}" => $npcuser_stat_json);
                    $redis->expire("Maker$npcuser_stat->{userid}" , 32 ); #32秒保持する
                    undef $npcuser_stat_json;
                 }

                $timelinelog->insert_one($npcuser_stat);

             undef $debmsg;

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
                  Loging("DEBUG: WRITECHAT: $debmsg");
               my $chatjson = to_json($chatobj);
                  $redis->publish( $chatname , $chatjson );
                  $walkchatcoll->insert_one($chatobj);              

                  undef $debmsg;
                  undef $npcuser_stat;
                  undef $chatjson;
                  undef $dt;
                  
                  return;
}

sub nullcheckgacc {
        # アカウントリストをチェックして差分を確認する
        if ( ! defined $gacclist ){
           #初期は未定義なのでバイパスさせる
           return;
        }

        my @list = @$gacclist;
        if (!@list){
            $nullcount++;
            if ( $nullcount >= 3 ) {
                Loging("null account list 3 times!!!!");
                exit;
                }
        }
        undef @list;
        }

sub d_correction {
    # rundirectへの補正を検討する   d_correction($npcuser_stat,@pointlist); で利用する
    # 共通変数$lat $lngへ直接補正を行う
  #  my ( $npcuser_stat, $rundirect, @pointlist ) = @_;
    my ($npcuser_stat,@pointlist) = @_;

    Loging("DEBUG: d_correction: in: $rundirect");

    # 空なら0を返す
    if (! @pointlist){
        Loging("DEBUG: d_correction: out: $rundirect");
        return;
    }

    my @userslist;

    #自分を除外
    for my $i (@pointlist){
        if ( $i->{userid} eq $npcuser_stat->{userid}){
           next;
           }
        push(@userslist,$i);
    }

    # UNITが居ない場合
    if (! @userslist){
       Loging("DEBUG: d_correction: out: $rundirect");
       return;
    }

    # 追跡ターゲットが設定されていた場合,ターゲットは回避対象から外す
    if ( $npcuser_stat->{target} ){
        for (my $i=0; $i <= $#userslist; $i++){
            if ( $pointlist[$i]->{userid} eq $npcuser_stat->{target} ){
                 Loging("DROP userslist: $userslist[$i]->{name} ");
                 splice(@userslist,$i,1);
                 last;
            }
        } # for
    } # if

   my @usersdirect;

   # 距離と方角を計算する 距離が50m以下のみを抽出
   for my $i (@userslist){

              #直径をかけてメートルになおす lat lngの位置に注意
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($i->{loc}->{lng}, $i->{loc}->{lat});
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
              my $t_direct = geoDirect($lat, $lng, $i->{loc}->{lat}, $i->{loc}->{lng});

              my $dist_direct = { "dist" => $t_dist, "direct" => $t_direct };
              push(@usersdirect,$dist_direct) if ($t_dist < 50);    
   }

   # 50m以内に居ない
   if (! @usersdirect) {
       Loging("DEBUG: d_correction: out: $rundirect");
       return;
   }
   
   for my $i (@usersdirect){
       
       my $cul_direct = $rundirect - $i->{direct};

       if ( ($cul_direct > 45 ) || ($cul_direct < -45)){
          # 進行方向左右45度以外(補正範囲外）
          Loging("DEBUG: d_correction: out: $rundirect");
          return;
       }

       if (( $cul_direct < 45 ) && ( $cul_direct > 0)) {
          # 補正左に45度
          $rundirect = $rundirect - 45;
          if ($rundirect < 0 ) {
             $rundirect = 360 + $rundirect;
          } 
          Loging("DEBUG: d_correction: out: $rundirect");

          # lat lngへの補正
          latlng_correction($rundirect);
          return;
       }
       if (( $cul_direct > -45 ) && ( $cul_direct < 0 )) {
          # 補正右に45度
          $rundirect = $rundirect + 45;
          if ($rundirect > 360){
             $rundirect = $rundirect - 360;
          }
          Loging("DEBUG: d_correction: out: $rundirect");

          # lat lngへの補正
          latlng_correction($rundirect);
          return;
       }
   } # for
   Loging("DEBUG: d_correction: out: $rundirect");
   return;  # 念のため
} # d_crrection


sub latlng_correction {
    # d_correction用に補正したrundirectからlat or lngのどちらに補正するか判定する
    # 45度単位で分割して補正する
  #  my $rundirect = shift;

    if ( geoarea($lat,$lng) == 1 ){
        # 東経北緯
        if (( $rundirect > 315 )||( $rundirect < 45 )){
             # 北方向へ補正
             $lat = $lat + 0.0001;
             $lat = overArealat($lat);
             Loging("DEBUG: lat+ correction");
           } elsif (($rundirect > 45 ) || ( $rundirect < 135)){
             # 東方向へ補正
             $lng = $lng + 0.0001;
             $lng = overArealng($lng);
             Loging("DEBUG: lng+ correction");
           } elsif (( $rundirect > 135 ) || ( $rundirect < 225 )){
             # 南方向へ補正
             $lat = $lat - 0.0001;
             $lat = overArealat($lat);
             Loging("DEBUG: lat- correction");
           } elsif (( $rundirect > 225 ) || ( $rundirect < 315 )) {
             # 西方向へ補正
             $lng = $lng - 0.0001;
             $lng = overArealng($lng);
             Loging("DEBUG: lng- correction");
           }
       } elsif ( geoarea($lat,$lng) == 2) {
       # 西経北緯 

       } elsif ( geoarea($lat,$lng) == 3) {
       # 東経南緯

       } elsif ( geoarea($lat,$lng) == 4) {
       # 西経南緯
       
       }
}


##### main

    my $cv = AE::cv;
    my $t = AnyEvent->timer(
            after => 10,
            interval => 10,
               cb => sub {

        Loging("------------------------------LOOP START-----------------------------------");

#        Loging("run_gacclist name list --------");
#        foreach my $i (@$run_gacclist){
#           print "$i->{name}";
#           print " ";
#        }
#        print "\n";
#        Loging("run_gacclist list END  --------");
#
#        Loging("gacclist name list --------");
#        foreach my $i (@$gacclist){
#           print "$i->{name}";
#           print " ";
#        }
#        print "\n";
#        Loging("gacclist list END  --------");

      $redis->get("GACCon$ghostmanid", sub{
                     my $result = shift;
                        Loging("redis_two get start point ---------------------------------");
                        if ( ! defined $result) {
                                       Loging("Get Redis in result block PASSED!!! GACCon$ghostmanid");
                                       return;
                           }

                           $redis->del("GACCon$ghostmanid");

                         # redisへの更新
                            my $gacclist_add = from_json($result);
                            Loging(" REDIS GET GACCon$ghostmanid | $result");
                            push(@$run_gacclist,@$gacclist_add);  # 問答無用で追記する　
                            my $run_json = to_json($run_gacclist);
                            $redis->set("GACC$ghostmanid" => $run_json);
                            $redis->expire("GACC$ghostmanid" , 32 ); #32秒保持する
                            Loging("REDIS SET GACCon!!!");
                            undef $run_json;

                        Loging("redis_two get END point ---------------------------------");
      });   # $redis GACCon

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
                                     Loging("DROP run_gacclist $list[$i]->{name} ");
                                     last;
                                    } 
                                }
                                    @list = @$gacclist;
                                 for (my $i=0; $i <= $#list ; $i++){
                                     if ( $list[$i]->{userid} eq $messobj->{to}){
                                      splice(@$gacclist,$i,1);  
                                      Loging("trap HIT gacclist drop $list[$i]->{name}");
                                      last;
                                     }
                                 } # for

                                # redisへの更新
                                my $run_json = to_json($run_gacclist);
                                $redis->set("GACC$ghostmanid" => $run_json);
                                $redis->expire("GACC$ghostmanid" , 32 ); #32秒保持する
                                Loging("REDIS SET Attack check!!!");
                                undef $run_json;
                                undef @list;

                       # 元々はhitnameをsite1に送るが、db直結になりアカウント情報を持つのでhitnameを利用しない
                                Loging("$username 祓われた。。。");
                                if ( $timelineredis == 0 ) {
                                    $timelinecoll->delete_many({"userid" => "$messobj->{to}"}); # mognodb3.2
                                } elsif ( $timelineredis == 1 ){
                                    $redis->del("Maker$messobj->{to}"); 
                                }

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

                                #ランキング処理 ghostaccはexecemailは空
                                $redis->zadd('gscore', "$pcnt", "$messobj->{execemail}") if (defined $messobj->{execemail});

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
                  });  # redis subscribe
               $AECV->send;  
               $AECV->recv;

# redis lisner  get_gacclist!!
  $redis->get("GACC$ghostmanid", sub{
                     my $result = shift;

                        Loging("redis get start point ---------------------------------");

                        if ( ! defined $result) { 
                                       @$gacclist = ();
                                       Loging("Get Redis in result block PASSED!!!");
                                       return;
                           }
                     $gacclist = from_json($result) if ( defined $result );
                     Loging(" REDIS GET GACC"); 

                 foreach my $acc (@$gacclist){
                       Loging("GET REDIS Check $acc->{name}");

                       # gacclistから差分を追加する
                       if ( ! grep { $_->{userid} eq $acc->{userid} } @$run_gacclist ) {
                         push(@$run_gacclist,$acc);
                         my $debug = to_json($acc);
                         Loging("run_gacclist not match. ");
                         Loging("run_gacclist add: $debug");
                         undef $debug; 
                         } # if grep
                     }

               #   undef $gacclist;   # ATTACKCHNが動かなくなる

          #    });   # 10secの末尾に移動 全ての処理はredisのサブルーチン内で処理する

  # Maker get
  my $getMaker = $redis->keys("Maker*");

     #   nullcheckgacc();  # redis subの外へ
        npcinit();


 #アカウント配列のループ    ########################################
        foreach my $npcuser_stat (@$run_gacclist){

undef @pointlist;
undef $pointlist;
undef $targetlist;
undef $targets;
undef @makerlist; 

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


          #   Loging("LIFECOUNT: $npcuser_stat->{lifecount}");
                           $npcuser_stat->{lifecount}--; 
                           if ( $npcuser_stat->{lifecount} <= 0 ) {
                             Loging("Dead END... 時間切れで終了... $npcuser_stat->{name}");

                             my @list = @$run_gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $npcuser_stat->{userid}){

                                     $timelinecoll->delete_many({"userid" => "$npcuser_stat->{userid}"}) if $timelineredis == 0; # mognodb3.2
                                     $redis->del("Maker$npcuser_stat->{userid}") if $timelineredis == 1;

                                     splice(@$run_gacclist,$i,1);
                                 } 
                             } # for

                             # redisへの更新
                             my $run_json = to_json($run_gacclist);
                             $redis->set("GACC$ghostmanid" => $run_json);
                             $redis->expire("GACC$ghostmanid" , 32 ); #32秒保持する

                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit; 
                                 }
                             undef @list;
                             undef $run_json;
                             next; # foreach $npcuser_stat
                             }

           # mongo3.2用 1000m以内のデータを返す
           @pointlist = ();
           my $geo_points_cursole;
           if ( $timelineredis == 0 ){ 
              $geo_points_cursole = $timelinecoll->query({ geometry => {
                                                           '$nearSphere' => {
                                                           '$geometry' => {
                                                                type => "point",
                                                                "coordinates" => [ $npcuser_stat->{loc}->{lng} , $npcuser_stat->{loc}->{lat} ]},
                                                           '$minDistance' => 0,
                                                           '$maxDistance' => 1000
                                     }}});
           @pointlist = $geo_points_cursole->all; # 原則重複無しの想定
           } # timelineredis == 1の場合はMakerで処理される

           #makerをredisから抽出して、距離を算出してリストに加える。
           #  my @makerkeylist = $redis->keys("Maker*");  #以下に置き換え

                       $getMaker->cb(sub {
                                   my @cv = @_;
                                   undef @makeracclist;
                                   my ($result, $err) = $cv[0]->recv;
                                       if (defined $result) {
                                       foreach my $akey (@$result){
                                           $redis->get($akey,sub { 
                                                      my $result = shift;
                                                         if ( ! defined $result ){ 
                                                                      @makeracclist = ();
                                                                    Loging("DEBUG: CLEAR makeracclist#####");
                                                                      return;
                                                                  }
                                       Loging("DEBUG: GET makeracclist");
                                         my $makeracc = from_json($result);
                                         push (@makeracclist,$makeracc);                                   
                                         undef $makeracc;
                                }); 
                              } # foreach
                          } 
                     }); 

             foreach my $makerpoint (@makeracclist) {
           #  foreach my $aline (@makerkeylist) {
           #      my $makerpoint = from_json($redis->get($aline));  # keyからアカウント情報に読み替えていたが、AEで変更

                   if ( defined $makerpoint){
                      my $debug = to_json($makerpoint);
                      Loging("DEBUG: -------------------makerpoint: $debug");
                      undef $debug;

                      # radianに変換
                      my @s_p = NESW($npcuser_stat->{loc}->{lng}, $npcuser_stat->{loc}->{lat});
                      my @t_p = NESW($makerpoint->{loc}->{lng}, $makerpoint->{loc}->{lat});
                      my $t_dist = great_circle_distance(@s_p,@t_p,6378140);


                      if ( $t_dist < 1000) {

                      Loging("DEBUG: t_dist: $t_dist $npcuser_stat->{name} makerlist IN !!");

                       push (@makerlist, $makerpoint );
                       }
                   #   undef $makerpoint;
                      undef @s_p;
                      undef @t_p;
                      undef $t_dist;
                     } # if defined makerpoint
                   } # foreach makerpoint

                   # makerとメンバーリストを結合する
                   if (@pointlist){
                       push (@pointlist,@makerlist);
                   } else {
                       @pointlist = @makerlist;   # timelineredis==1の場合
                   }


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
                   Loging("TRAP on Event!!!!!!!");

                       #Chat表示 トラップ発動時に表示する
                       my $dt = DateTime->now( time_zone => 'Asia/Tokyo');

                        $chatobj->{geometry} = $npcuser_stat->{geometry};
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
                        $redis->expire( "$chatname" , 3600 );
                     #   Loging("DEBUG: $username publish WALKCHAT");
                        undef $chatjson;

                   for my $i (@trapevents){
                       my $debug = to_json($i);
                     # delete trapevent
                       Loging("DEBUG: drop trapevent: $debug");
                       $trapmemberlist->delete_one({ '_id' => $i->{_id}});
                   }
                   undef @trapevents;
                   undef $trapmember_cursole;

                   # MemberTimeLineからの削除
                   if ( $timelineredis == 0 ){
                       $timelinecoll->delete_many({"userid" => "$npcuser_stat->{userid}"}); # mognodb3.2
                   } elsif ( $timelineredis == 1) {
                       $redis->del("Maker$npcuser_stat->{userid}");
                   }

                   # NPCアカウントの終了処理 
                             my @list = @$run_gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $npcuser_stat->{userid}){
                                  splice(@$run_gacclist,$i,1);  
                                  Loging("trap HIT run_gacclist drop $list[$i]->{name}");
                                  last;
                                 }
                             }
                                @list = @$gacclist;
                             for (my $i=0; $i <= $#list ; $i++){
                                 if ( $list[$i]->{userid} eq $npcuser_stat->{userid}){
                                  splice(@$gacclist,$i,1);  
                                  Loging("trap HIT gacclist drop $list[$i]->{name}");
                                  last;
                                 }
                             }

                             # redisへの更新
                             my $run_json = to_json($run_gacclist);
                             $redis->set("GACC$ghostmanid" => $run_json);
                             $redis->expire("GACC$ghostmanid" , 32 ); #32秒保持する
                             Loging("Redis set Hit trapevent!");
                           
                             if ( !@$run_gacclist) {
                                 # 空なら終了
                                 exit;
                                 }
                             undef @list;
                             undef $run_json;
                             undef $dt;

                             next;  # アカウント消滅なので次へ
               } # if trapevents


      #   Loging("DB responce! $npcuser_stat->{status}");
          #  $pointlist = $hash->{pointlist};
            $pointlist = \@pointlist;
          #  weaken($pointlist);
            $targetlist = $pointlist;

          #  undef $hash;

       # timelineredis == 1 の場合、@makerからユニットを除外する
          if ( $timelineredis == 1 ) {
              my @tmp_makerlist = @makerlist;
                 @makerlist = ();
              foreach my $i (@tmp_makerlist){
                 push(@makerlist,$i) if ($i->{name} eq 'maker');
              } # foreach
          }

     # Makerがある場合の処理 targetをmakerに変更してstatをchaseに
       if (@makerlist) {

           my $spm = int(rand($#makerlist));

              $npcuser_stat->{target} = $makerlist[$spm]->{userid};
              $npcuser_stat->{status} = "chase";
              Loging("Mode change Chase! to Tower");
              writejson($npcuser_stat);
           #   $txtmsg = "タワーに行くよ！！！";
           #   $txtmsg = encode_utf8($txtmsg);
           #   $chatobj->{chat} = $txtmsg;
           #   writechatobj($npcuser_stat);
           #   undef $txtmsg;

       } # if @makerlist

           # {chasecnt}が剰余0になると分裂する chasecntが0は除外する 連続しないために5%の確率を付与する
           if ( ($npcuser_stat->{chasecnt} % 100 == 0) && ($npcuser_stat->{chasecnt} != 0) && ( int(rand(1000)) <= 50 ) ) {
              $ua->post("https://$server/ghostman/gaccput" => form => { c => "1", lat => "$lat", lng => "$lng" });
              Loging("SET UNIT ADD!!!!");
              $txtmsg = "分裂するよ！！！";
              $txtmsg = encode_utf8($txtmsg);
              $chatobj->{chat} = $txtmsg;
              writechatobj($npcuser_stat);
              $npcuser_stat->{chasecnt} = 0 if ( $npcuser_stat->{chasecnt} >= 1000);  # 1000でリセット
              undef $txtmsg;
           }

           # tower配置処理、chasecntが1000を前提にに確率で配置する 乱数がchasecntと一致した場合
           if ( ($npcuser_stat->{chasecnt} == int(rand(1000))) && ( int(rand(1000)) <= 100 ) ) {

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
              my $makerobj_json = to_json($maker_stat);
                 $redis->set("Maker$makeruid" => $makerobj_json);
                 $redis->expire("Maker$makeruid" => 600); 

              $txtmsg = "タワーを設置したよ！！";
              $txtmsg = encode_utf8($txtmsg);
              $chatobj->{chat} = $txtmsg;
              writechatobj($npcuser_stat);
              undef $txtmsg;
           } # if



    # モード別の処理の前にユーザーを判別して追跡か逃走か判別する処理を加える
    # 追跡か逃走かの判別をどこで行うか検討が必要
    # ターンの初めに、USERを:chaseする:ghostが居るかを判定して、mode変更を行う。

    my $skipflg = 0;   # targetがmakerの場合を判定する
    if ( $npcuser_stat->{status} eq 'chase' ) {
         for my $i ( @makerlist ) {
             if ( $npcuser_stat->{target} eq $i->{userid} ){
                 $skipflg = 1;   # makerを追っている
                 last;
             }
         }
    }  # if chase     


    # tower優先処理では以下の処理はパスする。
    if ( $skipflg == 0 ) {   # makerをtargetしている場合はパスする

    # ghostが誰もUSERを追尾していないか判定する
    my $utarget_chk = 0;
    my @usercnt = ();
    my @utargetchk = ();

    for my $i (@$targetlist){ 
        if ( $i->{category} ne "USER" ){
            next;
        }
        push(@usercnt,$i);

        my @utarget = (); # USERをchaseターゲットしているghost
        for my $j (@$targetlist){
            if (( $j->{target} eq $i->{userid} ) && ( $j->{status} eq "chase")) {
               push(@utarget,$j); 
            }
        } # for j

        push(@utargetchk,\@utarget) if (@utarget);  # USER毎にghostがターゲットしているリスト 空は追加しない:
    } # for i

    if (@utargetchk){
        if ($#utargetchk == $#usercnt ){
            # USER数とtargetリストが一致していれば、少なくとghostは追跡している
            $utarget_chk = 1;
            Loging("DEBUG: enough ghost chase. $npcuser_stat->{name}");

            for my $i (@utargetchk){
                for my $j (@$i){
                    Loging("DEBUG: TARGET CHK: $j->{name} | TARGET: $j->{target}");
                }
            } # for
        } # if

    } else {
        $utarget_chk = 0; # USERがtargetされていない
        Loging("DEBUG: not enough ghost chase. Change mode $npcuser_stat->{name}");
    }

    if ( $utarget_chk == 0 ) {   # USERがtargetされていない
        for my $i (@$targetlist){
            if (($i->{category} eq "USER" ) && ( int(rand(100)) > 50 )) {
              my @s_p = NESW($lng, $lat);
              my @t_p = NESW($i->{loc}->{lng}, $i->{loc}->{lat});
              my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
               
                if ( $t_dist > (100 + int(rand(100))) ) {  # 100m + 100までのrand
                     if ( int(rand(100)) < 95 ) {
                         $npcuser_stat->{status} = "chase"; 
                         last;
                     } elsif ( int(rand(100)) < 95) {
                         $npcuser_stat->{status} = "round"; 
                         last;
                     }
                }  

                if ( $t_dist < (100 + int(rand(100))) ) {
                     if ( int(rand(100)) < 95 ) {
                         $npcuser_stat->{status} = "runaway";
                         last;
                     } elsif ( int(rand(100)) < 95) {
                         $npcuser_stat->{status} = "round";
                         last;
                     } elsif ( int(rand(100)) < 99) {
                         $npcuser_stat->{status} = "search";
                         last;
                     }
                }
            } # if 
        } # for
        } # if utarget_chk
    } # if skipflg

# 2時間に１回　search:モードに変更する
    if ( $npcuser_stat->{lifecount} % 720 == 0 ) {
         Loging("Change mode search.... for 2hours");
         $npcuser_stat->{status} = "search";
    }

# ここから下はnpcuser_stat->{status}で処理が分かれる

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

                # 補正
                d_correction($npcuser_stat,@pointlist);

                # モード変更チェック 

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

                   # 乱数によるモード変更
                   if (int(rand(50)) > 48) {

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
                   } elsif (int(rand(50)) > 48 ) {

                        if ($#chk_targets == -1) { next; } #pass

                        $npcuser_stat->{status} = "chase";
                        Loging("Mode change Chase!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "追跡モードになったよ！";
                        $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                      #  writechatobj($npcuser_stat);
                        next;
                   } elsif (int(rand(50)) > 48 ) {

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
                   } elsif (int(rand(50)) > 48 ) {

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

       #         #スタート地点からの距離判定
       #         # radianに変換
       #         my @s_p = NESW($lng, $lat);
       #         my @t_p = NESW($s_lng, $s_lat);
       #         my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
       #         undef @s_p;
       #         undef @t_p;
       #
       #         Loging("mode Random: $t_dist");
       #
       #         spnchange($t_dist);
       #
       #         # スタート地点から2km離れて、他に稼働するものがあれば、
       #         if ($t_dist > 2000 ){
       #
       #              @$targets = ();
       #              #自分をリストから除外する
       #              for my $i (@$targetlist){
       #                  if ( $i->{userid} eq $npcuser_stat->{userid}){
       #                  next;
       #                  }
       #                  push(@$targets,$i);
       #              }
       #
       #              my @t_list = @$targets;
       #              if ( $#t_list > 2 ){
       #                 $npcuser_stat->{status} = "chase";
       #                 Loging("Mode change Chase!");
       #                 my $txtmsg  = "追跡モードになったよ！";
       #                    $txtmsg = encode_utf8($txtmsg);
       #                 $chatobj->{chat} = $txtmsg;
       #              #   writechatobj($npcuser_stat);
       #                 undef @t_list;
       #                 next;
       #                 }
       #              undef @t_list;
       #         }  # t_dist > 2000 

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
              if ( ! defined $t_obj->{name} ) {
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

              my $addpoint = 0;

              my $directchk = 180;  # 初期値は大きく

                  $directchk = abs ( $t_direct - $t_obj->{rundirect}) ;
              #進行方向が同じ場合には、 追い越す:
              if (( $directchk < 45 ) && ($t_dist < 400 )){
                 $addpoint = (2 * ( $t_dist / 500000)) if ( defined $t_dist );   # 距離(m)を割る
                 Loging("DEBUG: addpoint: $addpoint $npcuser_stat->{name} ");
                 if ( ! defined $addpoint ) {
                     $addpoint = 0;
                 }
              } # if

              my $runway_dir = 1;   # default

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              if ( geoarea($lat,$lng) == 1 ) {

              # 追跡は速度を多めに設定 30m以上離れている場合は高速モード
              if ($runway_dir == 1) {
                 if ( $t_dist > 30 ) {
                        $lat = $lat + (( rand($point_spn) + 0.0001) + $addpoint);   # addpointは基本０ 条件で可算:
                        $lat = overArealat($lat);
                        $lng = $lng + (( rand($point_spn) + 0.0001) + $addpoint);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat + rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 2) {
                 if ( $t_dist > 30 ){
                        $lat = $lat - (( rand($point_spn) + 0.0001) + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng + (( rand($point_spn) + 0.0001) + $addpoint);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 3) {
                 if ( $t_dist > 30 ){
                        $lat = $lat - (( rand($point_spn) + 0.0001) + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng - (( rand($point_spn) + 0.0001) + $addpoint);
                        $lng = overArealng($lng);
                    } else {
                        $lat = $lat - rand($point_spn);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn);
                        $lng = overArealng($lng);
                          }}
              if ($runway_dir == 4) {
                 if ( $t_dist > 30 ){
                        $lat = $lat + (( rand($point_spn) + 0.0001) + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng - (( rand($point_spn) + 0.0001) + $addpoint);
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

              $addpoint = 0;   # 初期化:

                # 補正
                d_correction($npcuser_stat,@pointlist);

              # 5m以下に近づくとモードを変更
              if ($t_dist < 5 ) {

              # NPCがUSERに近づいた場合にカウントダウンをする  t_objとnpcuser_stat->{target}から算出
              # targetがUSERの場合
                if ( $t_obj->{category} eq "USER" ) {
                                # 履歴を読んでカウントダウンする
                                my $memcountobj = $membercount->find_one_and_delete({'userid'=>"$npcuser_stat->{target}"});
                                my $pcnt = 0;
                                   $pcnt = $memcountobj->{count} if ($memcountobj ne 'null');
                                   $pcnt = --$pcnt;
                                   $memcountobj->{count} = $pcnt;
                                   $memcountobj->{userid} = $npcuser_stat->{target};
                                   delete $memcountobj->{_id};
                                   $membercount->insert_one($memcountobj);
      
                                #ランキング処理
                                $redis->zadd('gscore', "$pcnt", "$t_obj->{email}");
                                Loging("TARGET: $t_obj->{name} count down... for $npcuser_stat->{name}");

                 } elsif ( $t_obj->{category} eq "NPC" ){
                     # NPC to NPC
                     my $hit_param = { to => $t_obj->{userid}, execute => $npcuser_stat->{userid} , execemail => "" }; #ghostaccは空にする
                     my $hitjson = to_json($hit_param);
                     $redis->publish( $attackCH , $hitjson );    
                     Loging("DEBUG: execute: $npcuser_stat->{name} to: $t_obj->{name}");
                     undef $hit_param;
                     undef $hitjson;
                 }

                 $npcuser_stat->{chasecnt} = ++$npcuser_stat->{chasecnt};
                 $npcuser_stat->{status} = "round"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 writejson($npcuser_stat);
                 Loging("Mode Change........round.");
                 my $txtmsg  = "roundモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 next;
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
                        next;
                  }

              # 確率で諦める
              if (($npcuser_stat->{status} eq "chase" ) && ( int(rand(100)) == $npcuser_stat->{chasecnt} )) {

                 # randomモードへ変更
                        $npcuser_stat->{status} = "random";
                        Loging("Mode change random!");
                        writejson($npcuser_stat);
                        my $txtmsg  = "ランダムモードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;
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
                #NPC以外のターゲットリスト
                     my @nonnpc_targets = ();
                     for my $i (@$targetlist){
                         if ( $i->{category} eq "NPC" ){
                         next;
                         }
                         push(@nonnpc_targets,$i);
                     }

             # CHECK
             my @chk_targets = @$targets;
             Loging("DEBUG: runaway Targets $#chk_targets ");

             if (($target eq "")&&($#chk_targets != -1)) {

                  if ( $#chk_targets >= 20 ){
                     # 無差別にターゲットを決定して、行動する
                     my @t_list = @$targets; 
                     my $lc = $#t_list;
                     my $tnum = int(rand($lc));
                     $target = $t_list[$tnum]->{userid};
                     $npcuser_stat->{target} = $target;
                     Loging("RUNAWAY target: $target : $lc : $tnum : $t_list[$tnum]->{name}"); 
                     undef @t_list;
                     undef $lc;
                     undef $tnum;

                    } elsif ($#nonnpc_targets != -1 ){
                      # ターゲットが20以下の場合nonnpc_targetsから選択
                      my $lc = $#nonnpc_targets;
                      my $tnum = int(rand($lc));
                      $target = $nonnpc_targets[$tnum]->{userid};
                      $npcuser_stat->{target} = $target;
                      Loging("RUNAWAY target: $target : $lc : $tnum : $nonnpc_targets[$tnum]->{name}"); 
                      undef $lc;
                      undef $tnum;
                    }

                } # if target="" chk_targets != -1

            # trapeventの設置
             if ( int(rand(1000)) > 998 ){ 

                 Loging("Trapeventの設置 $npcuser_stat->{name}");
                 my $evobj_stat = {
                             location => {
                                            type => "Point",
                                            coordinates => [ $lng , $lat ]
                                                   },
                              loc => {
                                             lat => $lat,
                                             lng => $lng
                                                     },
                             name => "mine",
                             status => "everyone",
                             ttl => "",
                             message => "TRAPに引っかかった！！！",
                             email => $npcuser_stat->{email},
                             };

                    $evobj_stat->{ttl} = DateTime->now();

                 $trapmemberlist->insert_one($evobj_stat);

             } # int(rand(100))

             #ターゲットステータスの抽出
             foreach my $t_p (@$targets){
                     if ( $t_p->{userid} eq $target){
                        $t_obj = $t_p;
                        }
                     } 
               
              # ターゲットをロストした場合、randomモードへ
              if (! defined $t_obj->{name} ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = ""; 
                 $npcuser_stat->{target} = ""; 
                 Loging("Mode Change........radom.");
                 # trap での自爆を避けるために少しずらす
                 $lat = $lat + 0.0001;
                 writejson($npcuser_stat);
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

              # 補正
              d_correction($npcuser_stat,@pointlist);

              #ターゲットが規定以下の場合は
              if (($#chk_targets < 20) && (int(rand(50) > 45))) {
                        $npcuser_stat->{status} = "round";
                        Loging("Mode change Round!");
                        writejson($npcuser_stat);

                        my $txtmsg  = "周回モードになったよ！";
                           $txtmsg = encode_utf8($txtmsg);
                        $chatobj->{chat} = $txtmsg;
                     #   writechatobj($npcuser_stat);
                        undef $txtmsg;
                        next;

              # 1000m以上に離れるとモードを変更
              } elsif (($t_dist > 1000 ) && ($#chk_targets > 20)) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 writejson($npcuser_stat);
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 next;
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
                         if ( $i->{category} eq "USER" ) {
                             for ( my $j=1; $j<=3 ; $j++ ){
                                 push(@$targets,$i);    # userを増やす
                             }
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
              if ( ! defined $t_obj->{name} ) {
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
              if ( rand(50) > 45 ) {
              if ( rand(100) > 50 ) { 
                                    $round_dire = 1;
                                   } else { 
                                    $round_dire = 2;
                  }
              } # out rand

              # 右回りプラス方向
              if ( $round_dire == 1 ) {
                  $t_direct = $t_direct + 45;
                  if ( $t_direct > 360 ) { $t_direct = $t_direct - 360; }
              } else {
                  # 左回りマイナス方向
                  $t_direct = $t_direct - 45;
                  if ( $t_direct < 0 ) { $t_direct = $t_direct + 360 ;}
                }
              $rundirect = $t_direct;

              my $runway_dir = 1;

              if ($t_direct < 90) { $runway_dir = 1; }
              if (( 90 <= $t_direct)&&( $t_direct < 180)) { $runway_dir = 2; }
              if (( 180 <= $t_direct)&&( $t_direct < 270 )) { $runway_dir = 3; }
              if (( 270 <= $t_direct)&&( $t_direct < 360 )) { $runway_dir = 4; }

              my $addpoint =  $t_dist / 500000 if ( defined $t_dist );   # 距離(m)を割る
                 if ( ! defined $addpoint ) {
                     $addpoint = 0.001;
                 }

              if ( geoarea($lat,$lng) == 1 ) {
              # 周回は速度を上乗せ
              if ($runway_dir == 1) {
                        $lat = $lat + rand($point_spn + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + $addpoint);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 2) {
                        $lat = $lat - rand($point_spn + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng + rand($point_spn + $addpoint);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 3) {
                        $lat = $lat - rand($point_spn + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + $addpoint);
                        $lng = overArealng($lng);
                          }
              if ($runway_dir == 4) {
                        $lat = $lat + rand($point_spn + $addpoint);
                        $lat = overArealat($lat);
                        $lng = $lng - rand($point_spn + $addpoint);
                        $lng = overArealng($lng);
                          }
              } elsif ( geoarea($lat,$lng) == 2 ) {

                 # 保留

              } elsif ( geoarea($lat,$lng) == 3 ) {

                 # 保留

              } elsif ( geoarea($lat,$lng) == 4 ) {

                 # 保留

              } # geoarea if

              $addpoint = 0; # 初期化

              # 補正
              d_correction($npcuser_stat,@pointlist);

              if ( int(rand(100)) > 95 ) {
                 $npcuser_stat->{status} = "random"; 
                 $target = "";
                 $npcuser_stat->{target} = "";
                 writejson($npcuser_stat);
                 Loging("Mode Change........radom.");
                 my $txtmsg  = "Randomモードになったよ！";
                    $txtmsg = encode_utf8($txtmsg);
                 $chatobj->{chat} = $txtmsg;
              #   writechatobj($npcuser_stat);
                 undef $txtmsg;
                 next;
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
                        next;
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

                   my $sel = int(rand(1));    # @keywordは2次元で　０，１を選ぶ
                   my @tmp = @{$keyword[$sel]};

                   my $selnum = int(rand($#tmp));
                   my $keywd = $keyword[$sel][$selnum];
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
                    Loging("DEBUG: slice: $slice");
                    my $deb = to_json($spointlist[$slice]);
                    Loging("DEBUG: slice: $deb");
                    undef $deb;

                    $npcuser_stat->{place}->{lat} = $spointlist[$slice]->{geometry}->{location}->{lat} + 0;
                    $npcuser_stat->{place}->{lng} = $spointlist[$slice]->{geometry}->{location}->{lng} + 0;
                    $npcuser_stat->{place}->{name} = $spointlist[$slice]->{name};

                    my $txtmsg = "今から$npcuser_stat->{place}->{name}へ行くよ！";
                       $txtmsg = encode_utf8($txtmsg);
                    $chatobj->{chat} = $txtmsg;
                    writechatobj($npcuser_stat);
                    undef $txtmsg;

                    Loging("DEBUG: Place: $npcuser_stat->{place}->{name} $npcuser_stat->{place}->{lat} $npcuser_stat->{place}->{lng}");

                    undef $slice;
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

                # 補正
                d_correction($npcuser_stat,@pointlist);

                my @s_p = NESW($lng, $lat);
                my @t_p = NESW($npcuser_stat->{place}->{lng}, $npcuser_stat->{place}->{lat});
                my $t_dist = great_circle_distance(@s_p,@t_p,6378140);
                Loging("DEBUG: dist: $t_dist");
                undef @s_p;
                undef @t_p;

                spnchange($t_dist);

               if ( $t_dist < 5 ) {
                   $point_spn = 0.0003;  #元に戻す
                   $npcuser_stat->{point_spn} = 0.0003;
                   $npcuser_stat->{chasecnt} = ++$npcuser_stat->{chasecnt};   # searchの完了もカウントアップとする
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
                   next;
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

      } #foreach $run_gacclist   ######################################################
      # 以上は10秒毎に実行されるアカウントループ

     # redis 書き込み
     my $run_json = to_json($run_gacclist);
        $redis->set("GACC$ghostmanid" => $run_json);
        $redis->expire("GACC$ghostmanid" , 32 ); #32秒保持する
        undef $run_json;
        Loging("SET REDIS WRITE finish");

        Loging("redis get end point ---------------------------------");

     });  # redis sub

    nullcheckgacc();

 #   undef $gacclist;   # 最後に消す  ...プロセスが終了しない。

#   my  $psize = total_size(\%main::);
#   Loging("main: $psize");
#    Dump(\%main::);
#Loging("-----find-----");
#find_cycle($timelinecoll);
#find_cycle($timelinelog);

#Loging("gacclist check");
#Dump($gacclist);
#Loging("run_gacclist check");
#Dump($run_gacclist);
#Loging("chatobj check");
#Dump($chatobj);
#Loging("username check");
#Dump($username);
#Loging("rundirect check");
#Dump($rundirect);


        Loging("---------------------LOOP END-----------------------------------");
    #   $cv->send;  # never end loop
       });  # AnyEvent CV 

    $cv->recv;

