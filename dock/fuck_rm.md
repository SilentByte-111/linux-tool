# Fuck RM - Linux 系统安全防护工具
[返回目录](dock.md)

## 介绍

`Fuck RM` 是一个 Linux 系统安全防护脚本 (`fuck_rm.sh`)，旨在防止用户误执行危险的系统命令，特别是那些可能导致系统损坏或数据丢失的命令。

## 简称：去你妈的还想删库跑路！

## 功能特性

### 1. 安全的 rm 命令
- 防止删除根目录 (`/`)
- 检测并阻止 `rm -rf /` 类型的危险命令组合
- 在需要时可通过完整路径 `/bin/rm` 调用原始命令

### 2. 安全的 dd 命令
- 阻止直接向磁盘设备（如 `/dev/sda`, `/dev/nvme0n1` 等）写入数据
- 防止意外覆盖整个硬盘

### 3. 格式化命令限制
- 限制 `mkfs` 相关命令的直接使用
- 需要使用完整路径（如 `/sbin/mkfs.ext4`）才能执行格式化操作

### 4. 安全的 chmod 命令
- 防止递归地给根目录设置过于宽松的权限（如 `chmod -R 777 /`）

## 安装方式

在终端输入一键安装代码：

```bash
 curl -sSL https://raw.githubusercontent.com/Xiaoxinyun2008/linux-tool/main/install.sh | tr -d '\r' | sudo bash -s --
```

## 安装后如何使用

- 自动创建路径地址为：/usr/local/bin
- 自动设置为全局命令功能
- 输入 `fuck_rm` 自动启用脚本功能

## 绕过保护

当确实需要执行保护命令时，可以使用完整路径：

```bash
/bin/rm -rf /path/to/delete
/bin/dd if=input of=output
/sbin/mkfs.ext4 /dev/sdX
```

## 恢复原始状态

如需恢复原始命令行为，可使用：

```bash
sudo bash /root/restore_commands.sh
```

## 注意事项

1. 此脚本主要防范误操作，不能完全替代良好的安全实践
2. Root 用户仍可通过完整路径执行原始命令
3. 建议配合其他安全措施，如定期备份、权限管理等
4. 所有配置会被备份，便于恢复