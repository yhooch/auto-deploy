#!/bin/bash

# 自动部署脚本

ROOT_PATH=$(cd $(dirname $0);pwd)

# 获取md-files文件夹下所有.md文件
md_files=$(find $ROOT_PATH/files/md -name "*.md")

# 创建每个.md文件的名称作为文件夹名
for md_file in $md_files; do
  dir_name=$(basename $md_file .md)
  mkdir -p $ROOT_PATH/$dir_name

  # 将该md文件移动到新创建的文件夹下
  cp $md_file $ROOT_PATH/$dir_name/

  # start.sh和update.sh到该文件夹下
  cp $ROOT_PATH/files/start.sh $ROOT_PATH/$dir_name/
  cp $ROOT_PATH/files/update.sh $ROOT_PATH/$dir_name/

  echo "init $md_file"

  # 将复制的update.sh配置到系统定时任务每分钟执行
  echo "2-59/3 * * * * cd $ROOT_PATH/$dir_name && ./update.sh" >> mycron.tmp
done

echo "1-59/3 * * * * cd $ROOT_PATH && ./daemon.sh" >> mycron.tmp

# 读取现有的定时任务
crontab -l > mycron

# 将新的定时任务追加到mycron.tmp中
cat mycron.tmp >> mycron

# 将mycron写入crontab
crontab mycron

echo "write crontab"

# 删除临时文件
rm mycron mycron.tmp

rm -rf $ROOT_PATH/files

rm $ROOT_PATH/init.sh
