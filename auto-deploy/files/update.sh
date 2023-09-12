#!/bin/bash

# shellcheck disable=SC2181,SC2086,SC2004,SC2164,SC2046

ROOT_PATH=$(cd $(dirname $0);pwd)

# 指定本地目录
LOCAL_DIR=$ROOT_PATH

LOG_FILE=$LOCAL_DIR/update.log

TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")

echo "$TIMESTAMP: ***********check update start..." | tee -a $LOG_FILE

# 从nacos中获取配置并且指定远程主机的IP地址、账号和密码
NACOS_SERVER_IP="nacos.crm.broadxt.com"
NACOS_SERVER_PORT="38848"
NACOS_NAMESPACE="10cd5390-b6b4-49b3-8e9e-6ac7c8267a62"
FILE_TYPE="properties"

# Config info
DATA_ID="jar-repository"
GROUP="DEFAULT_GROUP"

# Get config
CONFIG=$(curl -s "http://$NACOS_SERVER_IP:$NACOS_SERVER_PORT/nacos/v1/cs/configs?dataId=$DATA_ID&group=$GROUP&tenant=$NACOS_NAMESPACE&contentType=${FILE_TYPE}")

# 检查 curl 命令的退出状态，如果失败则退出脚本并显示错误消息

if [ $? -ne 0 ]; then
  echo "$TIMESTAMP: 无法从 Nacos 服务器检索配置，退出执行" | tee -a $LOG_FILE
  exit 1
fi

REMOTE_IP=$(echo "${CONFIG}" | grep "remote_ip" | cut -d'=' -f2)
REMOTE_DIR=$(echo "${CONFIG}" | grep "remote_dir" | cut -d'=' -f2)
REMOTE_USER=$(echo "${CONFIG}" | grep "remote_user" | cut -d'=' -f2)
REMOTE_PASS=$(echo "${CONFIG}" | grep "remote_pass" | cut -d'=' -f2)

#REMOTE_IP=<REMOTE_IP>
#REMOTE_DIR=<REMOTE_DIR>
#REMOTE_USER=<REMOTE_USER>
#REMOTE_PASS=<REMOTE_PASS>

DOWNLOAD_DIR="$LOCAL_DIR/download"
BACKUP_DIR="$LOCAL_DIR/backup"


# 下载目录
mkdir -p "$DOWNLOAD_DIR"
# 备份目录
mkdir -p "$BACKUP_DIR"

# 获取当前目录下所有 .md 文件名称并排序
MD_FILES=$(find "$LOCAL_DIR" -maxdepth 1 -type f -name "*.md" | head -n 1)

# 检查是否存在 .md 文件，如果不存在则结束执行
if [ -z "$MD_FILES" ]; then
  echo "$TIMESTAMP: 没有找到 .md 文件" | tee -a $LOG_FILE
  exit 1
fi

FILENAME=$(basename "$MD_FILES")

# 获取第一个 .md 文件名称并截取 .md 之前内容
PREFIX=$(echo "$FILENAME" | head -n 1 | sed 's/\.md$//')

# jar文件名称
JAR_FILE="${PREFIX}-[0-9].[0-9].[0-9].jar"

# 获取本地目录中指定前缀名称的文件的MD5值
LOCAL_MD5=$(find "$LOCAL_DIR" \
  -maxdepth 1 \
  -type f \
  -name "$JAR_FILE" \
  -printf '%T@ %p\n' |
  sort -nrk1,1 |
  head -n1 |
  awk '{print $2}' |
  xargs md5sum |
  awk '{ print $1 }')

# 获取远程目录中指定前缀名称的文件
function get_remote_file() {
  sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_IP" "find $REMOTE_DIR \
		-type f \
		-name '$JAR_FILE' \
		-printf '%T@ %p\n' \
		| sort -nrk1,1 \
		| head -n1"
}

retry_count=0
while [ $retry_count -lt 5 ]; do
    result=$(get_remote_file)
    exit_code=$?
    if [ $exit_code -ne 0 ]; then
        echo "$TIMESTAMP: ssh命令执行失败，错误码：$exit_code" | tee -a $LOG_FILE
        retry_count=$((retry_count + 1))
        continue
    fi

    if [ -z "$result" ]; then
        echo "$TIMESTAMP: 未找到远程文件，退出" | tee -a $LOG_FILE
        exit 1
    else
        echo "$TIMESTAMP: 找到远程文件" | tee -a $LOG_FILE
        break
    fi
done

if [ $retry_count -ge 4 ]; then
    echo "重试次数已达最大值，退出"
    exit 1
fi


# 获取远程目录中指定前缀名称的文件的MD5值
function get_remote_md5() {
  sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_IP" "find $REMOTE_DIR \
    -type f \
    -name '$JAR_FILE' \
    -printf '%T@ %p\n' \
    | sort -nrk1,1 \
    | head -n1 \
    | awk '{print \$2}' \
    | xargs md5sum \
    | awk '{ print \$1 }'"
}

MD5_MAX_RETRY=5
# 获取远程目录中指定前缀名称的文件的MD5值，增加重试机制
for ((i = 1; i <= $MD5_MAX_RETRY; i++)); do

  REMOTE_MD5=$(get_remote_md5)

  if [ ! $REMOTE_MD5 ]; then
    echo "$TIMESTAMP: 无法获取远程文件的MD5值，进行第 $((i + 1)) 次重试..." | tee -a $LOG_FILE
  else
    break
  fi

  if [ $i -eq $MD5_MAX_RETRY ]; then
    echo "$TIMESTAMP: 无法获取远程文件的MD5值，达到最大重试次数" | tee -a $LOG_FILE
    exit 1
  fi
done

# 比较MD5值，如果相同则文件一致，否则下载文件
if [ "$LOCAL_MD5" = "$REMOTE_MD5" ]; then
  echo "$TIMESTAMP: 文件一致" | tee -a $LOG_FILE
else
  echo "$TIMESTAMP: 文件不一致，开始下载远程文件..." | tee -a $LOG_FILE

  # 设置最大重试次数和初始等待时间
  MAX_RETRY=1
  WAIT_TIME=2s

  # 进行最多5次重试
  for ((i = 1; i <= $MAX_RETRY; i++)); do
    # 下载远程文件rsync
    sshpass -p "$REMOTE_PASS" rsync -avz --progress "$REMOTE_USER@$REMOTE_IP:$(sshpass -p "$REMOTE_PASS" ssh "$REMOTE_USER@$REMOTE_IP" "find $REMOTE_DIR \
    -type f \
    -name '$JAR_FILE' \
    -printf '%T@ %p\n' \
    | sort -nrk1,1 \
    | head -n1 \
    | awk '{print \$2}'")" "$DOWNLOAD_DIR"

    # 校验下载的文件完整性
    DOWNLOADED_FILE=$(find "$DOWNLOAD_DIR" \
      -maxdepth 1 \
      -type f \
      -name "$JAR_FILE" \
      -printf '%T@ %p\n' |
      sort -nrk1,1 |
      head -n1 |
      awk '{print $2}')

    DOWNLOADED_MD5=$(md5sum "$DOWNLOADED_FILE" | awk '{ print $1 }')

    echo "$TIMESTAMP: 文件下载成功并校验完整性" | tee -a $LOG_FILE

    if [ "$REMOTE_MD5" = "$DOWNLOADED_MD5" ]; then

      # 备份本地目标路径下相同前缀的文件到备份文件夹下
      find "$LOCAL_DIR/" \
        -maxdepth 1 \
        -type f \
        -name "$JAR_FILE" \
        -exec mv {} "$BACKUP_DIR" \;

      # 将下载的文件移动到目标路径下
      find "$DOWNLOAD_DIR/" \
        -maxdepth 1 \
        -type f \
        -name "$JAR_FILE" \
        -exec mv {} "$LOCAL_DIR/" \;

      echo "$TIMESTAMP: 检验一致，启动程序" | tee -a $LOG_FILE

      # 调用本地脚本
      bash $ROOT_PATH/start.sh restart

      break
    else
      # 如果未达到最大重试次数
      if [ $i -lt $MAX_RETRY ]; then
        echo "$TIMESTAMP: 文件校验失败，${WAIT_TIME}后进行第 $((i + 1)) 次重试" | tee -a $LOG_FILE

        sleep "$WAIT_TIME"

        # 增加等待时间
        WAIT_TIME="$((${WAIT_TIME%[a-z]} + 5))m"
      else
        echo "$TIMESTAMP: 文件校验失败，达到最大重试次数" | tee -a $LOG_FILE
      fi
    fi

  done

fi

echo "$TIMESTAMP: finish." | tee -a $LOG_FILE
