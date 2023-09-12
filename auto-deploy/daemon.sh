#!/bin/bash

# 检测子目录下有pid文件存在的进程是否存活，进程停止了就启动

ROOT_PATH=$(cd $(dirname $0);pwd)

# 获取当前目录下的所有子目录
directories=$(find $ROOT_PATH -type d)

LOG_FILE=$ROOT_PATH/daemon.log
TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

for directory in $directories
do
  # 检查pid.pid文件是否存在
  pid_file="$directory/pid.pid"
  if [ -f "$pid_file" ]; then
    # 读取pid文件中的进程号
    pid=$(cat "$pid_file")
    # 检查该进程是否存在
    if ps -p "$pid" > /dev/null; then
      echo "$TIMESTAMP: Process with PID $pid is running." #>> $LOG_FILE
    else
      # 执行start.sh脚本
      echo "$TIMESTAMP: Process with PID $pid in $directory is not running. Starting..." >> $LOG_FILE
      (cd "$directory" && ./start.sh restart)
    fi
  fi
done
