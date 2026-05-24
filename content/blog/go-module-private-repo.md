---
title: "Go Module 与 私有库"
date: 2020-02-27
slug: "go-module-private-repo"
---

> 由于公司 vcs 设置缘故 项目基本存在于 subgroup 下 且 import 路径也有属于 project 的 subdir
> 这就需要公司的 vcs 能够适应 ?go-get=1 访问 subdir 或 subgroup 时能给出正确的 clone 地址

## 问题背景

> 公司 vcs 系统使用 gitlab-ce 10.6.5 版本
> 源码 module 保存在 subgroup 和 subdir 下
> vcs 没有 https 端点

## 调查范围

1. module get 的工作方式
2. gitlab 响应逻辑
3. 正常工作的必要条件
4. 认证
5. 联通
6. 编译

## 实际工作

### 服务搭建与配置

#### 证书与签名

> [英文参考](https://www.akadia.com/services/ssh_test_certificate.html)

##### 自签名证书

```bash
# 1.生成私钥
$ openssl genrsa -out server.key 2048

# 2.生成 CSR (Certificate Signing Request)
$ openssl req -new -key server.key -out server.csr

# 3.生成自签名证书
$ openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt
```

##### 自建 CA 签名证书

```bash
# 1.创建 CA 私钥
$ openssl genrsa -out ca.key 2048

# 2.生成 CA 的自签名证书
$ openssl req -new -x509 -days 3650 -key ca.key -out ca.crt

# 3.生成需要颁发证书的私钥
$ openssl genrsa -out server.key 2048

# 4.生成要颁发证书的证书签名请求，证书签名请求当中的 Common Name 必须区别于 CA 的证书里面的 Common Name
$ openssl req -new -key server.key -out server.csr

# 5.用 2 创建的 CA 证书给 4 生成的 签名请求 进行签名
$ openssl x509 -req -days 3650 -in server.csr -CA ca.crt -CAkey ca.key -set_serial 01 -out server.crt
```

### 工具访问与尝试

#### 模拟访问

##### CURL 模拟
##### POSTMAN 模拟
##### HTTPie 模拟

#### go mod 访问

### 源码阅读与分析

#### gitlab 源码 Go Middleware 部分
#### go mod 源码 Module Lookup 部分

## 总结

### 外部评价
### 内部评价

## 附录

### 多级证书签名

```bash
# 生成根 CA 并自签（Common Name 填 RootCA）
$ openssl genrsa -des3 -out keys/RootCA.key 2048
$ openssl req -new -x509 -days 3650 -key keys/RootCA.key -out keys/RootCA.crt
# 生成二级 CA（Common Name 填 SecondCA）
$ openssl genrsa -des3 -out keys/secondCA.key 2048
$ openssl rsa -in keys/secondCA.key -out keys/secondCA.key
$ openssl req -new -days 3650 -key keys/secondCA.key -out keys/secondCA.csr
$ openssl ca -extensions v3_ca -in keys/secondCA.csr -config /etc/pki/tls/openssl.cnf -days 3650 -out keys/secondCA.crt -cert keys/RootCA.crt -keyfile keys/RootCA.key
# 生成三级 CA（Common Name 填 ThirdCA）
$ openssl genrsa -des3 -out keys/thirdCA.key 2048
$ openssl rsa -in keys/thirdCA.key -out keys/thirdCA.key
$ openssl req -new -days 3650 -key keys/thirdCA.key -out keys/thirdCA.csr
$ openssl ca -extensions v3_ca -in keys/thirdCA.csr -config /etc/pki/tls/openssl.cnf -days 3650 -out keys/thirdCA.crt -cert keys/secondCA.crt -keyfile keys/secondCA.key
# 使用三级 CA 签发服务器证书
$ openssl genrsa -des3 -out keys/server.key 2048
$ openssl rsa -in keys/server.key -out keys/server.key
$ openssl req -new -days 3650 -key keys/server.key -out keys/server.csr
$ openssl ca -in keys/server.csr -config /etc/pki/tls/openssl.cnf -days 3650 -out keys/server.crt -cert keys/thirdCA.crt -keyfile keys/thirdCA.key
```

### build -x

> 使用 go build -x 能看到更多 go module build 期间更多的细节

### go mod download

> modfetch 使用 BasicAuth 方式将登录信息注入 http 请求 [源码>](https://github.com/golang/go/blob/ee04dbf430de4343a3406253a132267bea38d3e6/src/cmd/go/internal/web/http.go#L89)
> auth 信息来源 解析 .netrc [源码>](https://github.com/golang/go/blob/ee04dbf430de4343a3406253a132267bea38d3e6/src/cmd/go/internal/auth/auth.go#L12)
