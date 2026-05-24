---
title: "使用 prometheus 监控应用性能"
date: 2020-02-16
slug: "prometheus-metrics"
---

## 引入：Pull 模型的服务监控

![Prometheus 生态](https://camo.githubusercontent.com/78b3b29d22cea8eee673e34fd204818ea532c171/68747470733a2f2f63646e2e6a7364656c6976722e6e65742f67682f70726f6d6574686575732f70726f6d65746865757340633334323537643036396336333036383564613335626365663038343633326666643564363230392f646f63756d656e746174696f6e2f696d616765732f6172636869746563747572652e737667)

### Pull 模型

> 由 Prometheus 向所有已知的 target 发送 http get $HOST:$PORT/metrics

- http get prometheus:9090/metrics

```bash
# HELP prometheus_tsdb_wal_page_flushes_total Total number of page flushes.
# TYPE prometheus_tsdb_wal_page_flushes_total counter
prometheus_tsdb_wal_page_flushes_total 5759
# HELP promhttp_metric_handler_requests_total Total number of scrapes by HTTP status code.
# TYPE promhttp_metric_handler_requests_total counter
promhttp_metric_handler_requests_total{code="200"} 1134
promhttp_metric_handler_requests_total{code="500"} 0
promhttp_metric_handler_requests_total{code="503"} 0
# HELP promhttp_metric_handler_requests_in_flight Current number of scrapes being served.
# TYPE promhttp_metric_handler_requests_in_flight  gauge
promhttp_metric_handler_requests_in_flight 1
# HELP prometheus_tsdb_wal_truncate_duration_seconds Duration of WAL truncation.
# TYPE prometheus_tsdb_wal_truncate_duration_seconds summary
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.5"} NaN
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.9"} NaN
prometheus_tsdb_wal_truncate_duration_seconds{quantile="0.99"} NaN
prometheus_tsdb_wal_truncate_duration_seconds_sum 0
prometheus_tsdb_wal_truncate_duration_seconds_count 0
prometheus_tsdb_wal_truncations_total 0
# HELP prometheus_tsdb_compaction_chunk_range_seconds Final time range
# TYPE prometheus_tsdb_compaction_chunk_range_seconds histogram
prometheus_tsdb_compaction_chunk_range_seconds_bucket{le="102400"} 1
prometheus_tsdb_compaction_chunk_range_seconds_bucket{le="1.6384e+06"} 594
prometheus_tsdb_compaction_chunk_range_seconds_bucket{le="6.5536e+06"} 2838
prometheus_tsdb_compaction_chunk_range_seconds_bucket{le="+Inf"} 2838
prometheus_tsdb_compaction_chunk_range_seconds_sum 4.489241e+09
prometheus_tsdb_compaction_chunk_range_seconds_count 2838
```

### 可视化效果

- [grafana](http://192.168.11.98:3000)
- [prometheus](http://192.168.11.98:9090/graph)

## 数据类型 与 指标定义

### 数据类型

- 计数器
  - 单调增加
- 示数器
  - 随意增减
- 分布
  - 分段统计 _bucket{le=""}
  - 计量 _sum
  - 计数 _count
- 摘要
  - 分位统计 {quantile=""}
  - 计量 _sum
  - 计数 _count

### 指标定义

#### 示例：Apdex score

[原文](https://prometheus.io/docs/practices/histograms/#apdex-score)

- Apdex 定义了应用响应时间的最优门槛为 T，另外根据应用响应时间结合 T 定义了三种不同的性能表现：
  - Satisfied（满意）：应用响应时间低于或等于 T
  - Tolerating（可容忍）：应用响应时间大于 T，但同时小于或等于 4T
  - Frustrated（烦躁期）：应用响应时间大于 4T
- 公式
  - Apdex = (Satisfied Count + Tolerating Count / 2) / Total Samples

### 讨论：指标与评价标准

#### 示例：指标

- 计算类别
  - 请求率
  - 错误率
  - 延迟
  - 饱和率
  - 利用率
- 输入类别
  - 内外部调用
  - 关键对象创建销毁
  - 请求接收与响应
  - 内部错误
  - 关键路径
- 计算类别 与 输入类别 正交得到相关类别的评价

#### service 埋点颗粒度

- machine
- container
- application
- request

## 澄清：与服务发现集成

> 是否需要桥接 天湖自己的服务发现

### 现有集成方式

- azure
- consul
- dns
- ec2
- file
- gce
- kubernetes
- marathon
- openstack
- triton
- zookeeper

## 附录

### demo

```go
// Copyright 2015 The Prometheus Authors
// Licensed under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License.
// You may obtain a copy of the License at
//
// http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software
// distributed under the License is distributed on an "AS IS" BASIS,
// WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
// See the License for the specific language governing permissions and
// limitations under the License.

// A simple example exposing fictional RPC latencies with different types of
// random distributions (uniform, normal, and exponential) as Prometheus
// metrics.
package main

import (
	"flag"
	"log"
	"math"
	"math/rand"
	"net/http"
	"time"

	"github.com/prometheus/client_golang/prometheus"
	"github.com/prometheus/client_golang/prometheus/promhttp"
)

var (
	addr              = flag.String("listen-address", ":8080", "The address to listen on for HTTP requests.")
	uniformDomain     = flag.Float64("uniform.domain", 0.0002, "The domain for the uniform distribution.")
	normDomain        = flag.Float64("normal.domain", 0.0002, "The domain for the normal distribution.")
	normMean          = flag.Float64("normal.mean", 0.00001, "The mean for the normal distribution.")
	oscillationPeriod = flag.Duration("oscillation-period", 10*time.Minute, "The duration of the rate oscillation period.")
)

var (
	rpcDurations = prometheus.NewSummaryVec(
		prometheus.SummaryOpts{
			Name:       "rpc_durations_seconds",
			Help:       "RPC latency distributions.",
			Objectives: map[float64]float64{0.5: 0.05, 0.9: 0.01, 0.99: 0.001},
		},
		[]string{"service"},
	)
	rpcDurationsHistogram = prometheus.NewHistogram(prometheus.HistogramOpts{
		Name:    "rpc_durations_histogram_seconds",
		Help:    "RPC latency distributions.",
		Buckets: prometheus.LinearBuckets(*normMean-5**normDomain, .5**normDomain, 20),
	})
)

func init() {
	prometheus.MustRegister(rpcDurations)
	prometheus.MustRegister(rpcDurationsHistogram)
	prometheus.MustRegister(prometheus.NewBuildInfoCollector())
}

func main() {
	flag.Parse()

	start := time.Now()

	oscillationFactor := func() float64 {
		return 2 + math.Sin(math.Sin(2*math.Pi*float64(time.Since(start))/float64(*oscillationPeriod)))
	}

	go func() {
		for {
			v := rand.Float64() * *uniformDomain
			rpcDurations.WithLabelValues("uniform").Observe(v)
			time.Sleep(time.Duration(100*oscillationFactor()) * time.Millisecond)
		}
	}()

	go func() {
		for {
			v := (rand.NormFloat64() * *normDomain) + *normMean
			rpcDurations.WithLabelValues("normal").Observe(v)
			rpcDurationsHistogram.Observe(v)
			time.Sleep(time.Duration(75*oscillationFactor()) * time.Millisecond)
		}
	}()

	go func() {
		for {
			v := rand.ExpFloat64() / 1e6
			rpcDurations.WithLabelValues("exponential").Observe(v)
			time.Sleep(time.Duration(50*oscillationFactor()) * time.Millisecond)
		}
	}()

	http.Handle("/metrics", promhttp.Handler())
	log.Fatal(http.ListenAndServe(*addr, nil))
}
```
