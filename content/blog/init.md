---
title: "Init"
date: 2020-02-16
slug: "init"
---

```make
release: build
	@cd zhangli2946.github.io && git add . && git commit -m "update" && git push

build:
	hugo -D
```
