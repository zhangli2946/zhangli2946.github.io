---
title: "Alpine Image"
date: 2020-06-26
slug: "alpine-image"
---

## 背景

- 公司使用的 alpine 镜像进行过网络参数调优
- 新项目 使用了 cgo (librdkafka-go-bindings)

## 冲突

- 想要在该项目中使用调优过的 alpine 镜像
- 该镜像不具备编译源代码能力
- librdkafka-go-bindings 需要编译时开启 cgo

## 结果

- 通过 多阶段编译 方式解决上面问题
  1. 使用 golang:alpine 环境 作为编译阶段的底包
  2. apk 安装 build-base vim git 等包组和实用工具
  3. 编译阶段产物 复制到最终阶段 (使用公司调优的 alpine)
- 形成了通用的 多阶段编译方案 (伸手党最爱)
  - 源码放置 相关 Dockerfile Makefile
  - ci 配置 编译路径
  - just build

## 感想

- 解决这个问题 使用的 go 库自带电池是非常贴心的
  - 大大降低了 折腾编译依赖库的成本
    - 对比同组的巨巨 手工编译依赖的代码库 我真是 一部到位
- 使用一个好的 底包也有很大关系
  - alpine 自带的包管理 使得我能够以最低成本调整出编译代码的必要环境
- 前期对问题的了解 也很重要
  - 问题识别不清楚 很容易抓不到核心矛盾
