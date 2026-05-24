---
title: "go module 访问私有库 (gitlab@11.10.4)"
date: 2020-02-16
slug: "go-module-gitlab"
---

## 开发环境 配置

> 推荐 编译环境升级 go 1.13+

### 启动 GOMOD 模式

#### 设置 GO1111MODULE

`go env -w GO111MODULE=on`

### 配置公有库依赖管理

#### 设置 GOPROXY

`go env -w GOPORXY=http://10.30.52.66:3000,direct`

### 配置私有库依赖管理

#### 设置 GOPRIVATE

`go env -w GOPRIVATE=$PRIVATE_REPO_HOST`

#### 设置 Git over HTTP(s) 免密

> 在 gitlab 注册后从 web 界面 获取 acceess token (编译环境 选只读; 开发环境 选读写)
> 通过 下述方式 进行免密配置后 不需要进行 ssh 证书添加

```bash
touch ~/.git-credentials
echo "http://$PRIVATE_REPO_USERNAME:$$PRIVATE_REPO_TOKEN@$PRIVATE_REPO_HOST" >> ~/.git-credentials
echo "https://$PRIVATE_REPO_USERNAME:$$PRIVATE_REPO_TOKEN@$PRIVATE_REPO_HOST" >> ~/.git-credentials
git config --global credential.helper store
```

#### 设置 Module 命令认证信息

> go mod 命令的认证信息 仅能从 主机登陆协议配置 $HOME/.netrc 中获取

```shell
cat >> $HOME/.netrc << EOF
machine gitlab.supos.ai login $USERNAME password $ACCESS_TOKEN
EOF
```

#### (optional) 针对私有库 为自签名 https 证书

- ubuntu

```bash
cp server.crt /usr/local/share/ca-certificates
update-ca-certificates
```

- centos

```bash
cp server.crt /etc/pki/ca-trust/source/anchors
update-ca-trust
```

- docker
  - 根据 baseimage 的 os 设定

## 编译环境 配置

> 与 开发环境雷同

## 附录

### 服务端 gitlab

#### 自签名证书

```
# 1.生成私钥
openssl genrsa -out server.key 2048
# 2.生成 CSR (Certificate Signing Request) commonName 对应被保护的 host
openssl req -new -key server.key -out server.csr
# 3.生成自签名证书
openssl x509 -req -days 3650 -in server.csr -signkey server.key -out server.crt
```

#### docker-compose.yml

```yaml
web:
  image: store/gitlab/gitlab-ce:11.10.4-ce.0
  restart: always
  hostname: 'supos.ai'
  environment:
    GITLAB_OMNIBUS_CONFIG: |
      external_url 'https://supos.ai'
      gitlab_rails['gitlab_shell_ssh_port'] = 2224
      unicorn['worker_timeout'] = 60
      unicorn['worker_processes'] = 5
      unicorn['worker_memory_limit_min'] = "200 * 1 << 20"
      unicorn['worker_memory_limit_max'] = "300 * 1 << 20"
      sidekiq['concurrency'] = 10
      gitlab_rails['backup_path'] = "/data/gitlab-backup"
      gitlab_rails['backup_keep_time'] = 1296000
      gitlab_rails['time_zone'] = 'Asia/Shanghai'
      gitlab_rails['backup_archive_permissions'] = 0644
      nginx['client_max_body_size'] = '10240m'
      nginx['enable'] = true
      nginx['http2_enabled'] = true
      nginx['listen_addresses'] = ["0.0.0.0"]
      nginx['ssl_certificate_key'] = "/etc/gitlab/certifacations/server.key"
      nginx['ssl_certificate'] = "/etc/gitlab/certifacations/server.crt"
      nginx['ssl_ciphers'] = "ECDHE-RSA-AES256-GCM-SHA384:ECDHE-RSA-AES128-GCM-SHA256"
      nginx['ssl_prefer_server_ciphers'] = "on"
      nginx['ssl_protocols'] = "TLSv1.1 TLSv1.2"
      nginx['ssl_session_cache'] = "builtin:1000  shared:SSL:10m"
      postgresql['max_worker_processes'] = 8
      postgresql['shared_buffers'] = "256MB"
  ports:
    - '80:80'
    - '443:443'
    - '2224:22'
  volumes:
    - './gitlab/config:/etc/gitlab'
    - './gitlab/logs:/var/log/gitlab'
    - './gitlab/data:/var/opt/gitlab'
```
