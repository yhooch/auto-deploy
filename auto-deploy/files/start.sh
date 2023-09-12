#!/bin/bash

ROOT_PATH=$(cd $(dirname $0);pwd)

JAVA_HOME=$ROOT_PATH/../java/jdk1.8.0_201
APP_ROOT=$ROOT_PATH/apps
PID_FILE=$ROOT_PATH/pid.pid
APP_LOG_ROOT=$ROOT_PATH/logs
SYSTEM_OUT_LOG_FILE=$ROOT_PATH/catalina.out

JAVA_OPTS="-server -Xms10g -Xmx10g"

RETVAL=0

start() {
 if [ -e $PID_FILE ];then
   echo "$PID_FILE already running...."
   exit 1
 fi

 if [ ! -d $APP_LOG_ROOT  ];then
    mkdir $APP_LOG_ROOT
 fi

   echo $"Starting $PID_FILE: "
   echo "JAVA_HOME=$JAVA_HOME"
   echo "APP_ROOT=$APP_ROOT"
   echo "LOGBACK_FILE=$LOGBACK_FILE"
   echo "SYSTEM.OUT_LOG_FILE=$SYSTEM_OUT_LOG_FILE"

   nohup $JAVA_HOME/bin/java -jar -Dapp.log=$APP_LOG_ROOT $JAVA_OPTS $ROOT_PATH/*.jar  >$SYSTEM_OUT_LOG_FILE  &

   RETVAL=$?
   if [ $RETVAL = 0 ]; then
     echo $!>$PID_FILE
   fi

   return $RETVAL
}

# Stop daemons functions.
stop() {
    echo  $"Stopping $PID_FILE: "

    if [ -e $PID_FILE ];then
      PID=`cat $PID_FILE`
      rm -f $PID_FILE
      P=`ps -p $PID|wc -l`
      if [ 2 -eq $P ]; then
         echo "kill process"
         kill  $PID
         sleep 3
      fi
      #double check
      P=`ps -p $PID|wc -l`
      if [ 2 -eq $P ]; then
         echo "kill process forcely"
         kill  -9 $PID
         sleep 1
      fi
    else
      echo "$PID_FILE not running"
    fi

    RETVAL=$?
    return $RETVAL
}



# See how we were called.
case "$1" in
start)
        start
        ;;

stop)
        stop
        ;;
restart)
        stop
        start
        ;;
*)
        echo $"Usage: $prog {start|stop|restart}"
        exit 1
esac

exit $RETVAL

