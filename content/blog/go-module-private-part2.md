---
title: "Go Module 与 私有库 (二)"
date: 2020-02-27
slug: "go-module-private-part2"
---

## 现状

- 公司当前使用 GitLab 版本 为 10.6.5
- 使用 Go Module 拉取 GitLab 中 个人目录下的项目 能够正常工作
- 使用 Go Module 拉取 GitLab 中 SubGroup/SubDirect 不能够正常工作
  - go get 解析到的地址为 gitlab.supos.ai/$GROUP/$SUBGROUP 用于拉取项目目录
  - 解析到的地址有误 不能进行后续动作

## 问题

### 背景

#### go get 查找 repo root 方式

```shell
go get -u -v gitlab.supos.ai/supos/datalake/common/log
get "gitlab.supos.ai/supos/datalake": found meta tag get.metaImport{Prefix:"gitlab.supos.ai/supos/datalake", VCS:"git", RepoRoot:"http://gitlab.supos.ai/supos/datalake.git"} at //gitlab.supos.ai/supos/datalake?go-get=1
get "gitlab.supos.ai/supos/datalake/common": found meta tag get.metaImport{Prefix:"gitlab.supos.ai/supos/datalake/common", VCS:"git", RepoRoot:"http://gitlab.supos.ai/supos/datalake/common.git"} at //gitlab.supos.ai/supos/datalake/common?go-get=1
get "gitlab.supos.ai/supos/datalake/common/log": found meta tag get.metaImport{Prefix:"gitlab.supos.ai/supos/datalake/common", VCS:"git", RepoRoot:"http://gitlab.supos.ai/supos/datalake/common.git"} at //gitlab.supos.ai/supos/datalake/common/log?go-get=1
get "gitlab.supos.ai/supos/datalake/common/log": verifying non-authoritative meta tag
go: finding gitlab.supos.ai/supos/datalake/common/log latest
gitlab.supos.ai/supos/datalake/common/log
```

- 由 log 可见 查找 repo root 的过程是根据 路径级别 递归查找
- 当进入 repo 的 subdir 时 返回的 RepoRoot 仍旧指向 repo 而非 其 subdir

#### go get 携带认证信息的方式

[源码位置](https://github.com/golang/go/blob/release-branch.go1.13/src/cmd/go/internal/auth/auth.go#L17)

```go
// Copyright 2019 The Go Authors. All rights reserved.
// Use of this source code is governed by a BSD-style
// license that can be found in the LICENSE file.

// Package auth provides access to user-provided authentication credentials.
package auth

import "net/http"

// AddCredentials fills in the user's credentials for req, if any.
// The return value reports whether any matching credentials were found.
func AddCredentials(req *http.Request) (added bool) {
	// TODO(golang.org/issue/26232): Support arbitrary user-provided credentials.
	netrcOnce.Do(readNetrc)
	for _, l := range netrc {
		if l.machine == req.URL.Host {
			req.SetBasicAuth(l.login, l.password)
			return true
		}
	}

	return false
}
```

[源码位置](https://github.com/golang/go/blob/6bf4b230234171f1cc4edab8e3eb2a989a02ddee/src/net/http/request.go#L959:19)

```go
func (r *Request) SetBasicAuth(username, password string) {
	r.Header.Set("Authorization", "Basic "+basicAuth(username, password))
}
```

[源码位置](https://github.com/golang/go/blob/6bf4b230234171f1cc4edab8e3eb2a989a02ddee/src/net/http/client.go#L341:6)

```go
func basicAuth(username, password string) string {
	auth := username + ":" + password
	return base64.StdEncoding.EncodeToString([]byte(auth))
}
```

#### GitLab 处理 ?go-get=1 请求的逻辑

[源码位置](https://gitlab.com/gitlab-org/gitlab-foss/blob/v10.6.5/lib/gitlab/middleware/go.rb#L25)

```ruby
 def project_path(request)
		...
        # We see if a project exists with any of these potential paths
        project = project_for_paths(project_paths, request)

        if project
          # If a project is found and the user has access, we return the full project path
          project.full_path
        else
          # If not, we return the first two components as if it were a simple `namespace/project` path,
          # so that we don't reveal the existence of a nested project the user doesn't have access to.
          # This means that for an unauthenticated request to `group/subgroup/project/subpackage`
          # for a private `group/subgroup/project` with subpackage path `subpackage`, GitLab will respond
          # as if the user is looking for project `group/subgroup`, with subpackage path `project/subpackage`.
          # Since `go get` doesn't authenticate by default, this means that
          # `go get gitlab.com/group/subgroup/project/subpackage` will not work for private projects.
          # `go get gitlab.com/group/subgroup/project.git/subpackage` will work, since Go is smart enough
          # to figure that out. `import 'gitlab.com/...'` behaves the same as `go get`.
          simple_project_path
        end
      end

      def project_for_paths(paths, request)
        project = Project.where_full_path_in(paths).first
        return unless Ability.allowed?(current_user(request), :read_project, project)

        project
      end

      def current_user(request)
        authenticator = Gitlab::Auth::RequestAuthenticator.new(request)
        user = authenticator.find_user_from_access_token || authenticator.find_user_from_warden

        return unless user&.can?(:access_api)

        # Right now, the `api` scope is the only one that should be able to determine private project existence.
        return unless authenticator.valid_access_token?(scopes: [:api])

        user
      end
```

[源码位置](https://gitlab.com/gitlab-org/gitlab-foss/blob/v10.6.5/lib/gitlab/auth/request_authenticator.rb#L24)

```ruby
      def valid_access_token?(scopes: [])
        validate_access_token!(scopes: scopes)
```

[源码位置](https://gitlab.com/gitlab-org/gitlab-foss/blob/v10.6.5/lib/gitlab/auth/user_auth_finders.rb#L49)

```ruby
      def validate_access_token!(scopes: [])
        return unless access_token
```

[源码位置](https://gitlab.com/gitlab-org/gitlab-foss/blob/v10.6.5/lib/gitlab/auth/user_auth_finders.rb#L64)

```ruby
      def access_token
        strong_memoize(:access_token) do
          find_oauth_access_token || find_personal_access_token
        end
      end

      def find_personal_access_token
        token =
          current_request.params[PRIVATE_TOKEN_PARAM].presence ||
          current_request.env[PRIVATE_TOKEN_HEADER].presence

        return unless token

        # Expiration, revocation and scopes are verified in `validate_access_token!`
        PersonalAccessToken.find_by(token: token) || raise(UnauthorizedError)
      end

      def find_oauth_access_token
        token = Doorkeeper::OAuth::Token.from_request(current_request, *Doorkeeper.configuration.access_token_methods)
        return unless token

        # Expiration, revocation and scopes are verified in `validate_access_token!`
        oauth_token = OauthAccessToken.by_token(token)
        raise UnauthorizedError unless oauth_token

        oauth_token.revoke_previous_refresh_token!
        oauth_token
      end
```

#### GitLab 10.6.5 Go Midware 行为

- 通过 project_path 递归查找 找到完整路径
- 返回 正确路径的条件时 能够找到 repo root 且认证通过 由权访问该 repo

### 根因

- 由背景 知道
  - go get 走 basicauth 携带认证信息
  - gitlab 用 PRIVATE_TOKEN 获得认证信息
  - 认证信息决定能否获得正确路径
- 故而的出无法使用的原因 --- 认证信息传递中断
