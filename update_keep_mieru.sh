#!/bin/bash
# 拉取上游 XiaoV2board 更新，同时保留本地 mieru 改动（本地提交会 rebase 到上游最新代码之上）
# 用法：在面板根目录执行  bash update_keep_mieru.sh
set -e

if [ ! -d ".git" ]; then
  echo "当前目录不是 git 部署，无法拉取更新。"
  exit 1
fi

git config --global --add safe.directory "$(pwd)"
BRANCH=$(git rev-parse --abbrev-ref HEAD)

# 有未提交改动先停下，避免丢失
if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "有未提交的改动，请先 git add -A && git commit -m '本地改动'，再运行本脚本。"
  git status --short
  exit 1
fi

git fetch origin
if ! git rebase origin/master; then
  echo "上游改动与 mieru 补丁冲突，已中止。"
  git rebase --abort
  echo "已恢复到更新前的状态。请把新版源码发来重新适配。"
  exit 1
fi

rm -rf composer.lock composer.phar
wget https://github.com/composer/composer/releases/latest/download/composer.phar -O composer.phar
php composer.phar update -vvv

php_main_version=$(php -v | head -n 1 | cut -d ' ' -f 2 | cut -d '.' -f 1)
if [ "$php_main_version" -ge 8 ]; then
  php composer.phar require joanhey/adapterman
  if ! php -m | grep -q "pcntl"; then
    sed -i '/extension=redis.so/a extension=pcntl.so' cli-php.ini
  fi
  php -c cli-php.ini webman.php stop || true
  echo "Webman 已停止，如在使用请手动启动：php -c cli-php.ini webman.php start -d"
fi

php artisan v2board:update
php artisan config:clear
php artisan config:cache
php artisan horizon:terminate

if [ -f "/etc/init.d/bt" ]; then
  chown -R www "$(pwd)"
fi
echo "更新完成（分支 $BRANCH），mieru 改动已保留。"
