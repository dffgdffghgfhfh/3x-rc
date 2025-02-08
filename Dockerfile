# ========================================================
# Stage: Builder
# ========================================================
FROM debian:bullseye-slim AS builder
WORKDIR /app
ARG TARGETARCH

# 安装构建依赖
RUN apt-get update && apt-get install -y \
  build-essential \
  gcc \
  wget \
  unzip \
  curl \
  && rm -rf /var/lib/apt/lists/*  # 清理 apt 缓存以减少镜像体积

# 下载 Go 1.23.6，使用正确的下载地址
RUN curl -LO https://dl.google.com/go/go1.23.6.linux-amd64.tar.gz \
    && echo "9379441ea310de000f33a4dc767bd966e72ab2826270e038e78b2c53c2e7802d  go1.23.6.linux-amd64.tar.gz" | sha256sum -c - \
    && tar -C /usr/local -xzf go1.23.6.linux-amd64.tar.gz \
    && rm go1.23.6.linux-amd64.tar.gz

ENV PATH="/usr/local/go/bin:${PATH}"

# 验证 Go 安装
RUN go version

COPY . .

ENV CGO_ENABLED=1
ENV CGO_CFLAGS="-D_LARGEFILE64_SOURCE"
RUN go build -ldflags "-w -s" -o build/x-ui main.go
RUN ./DockerInit.sh "$TARGETARCH"

# ========================================================
# Build biliup's web-ui
# ========================================================
FROM node:lts as webui
ARG repo_url=https://github.com/biliup/biliup
ARG branch_name=master
RUN set -eux; \
	git clone --depth 1 --branch "$branch_name" "$repo_url"; \
	cd biliup; \
	npm install; \
	npm run build


# ========================================================
# Stage: Final Image of 3x-ui (Debian base)
# ========================================================
FROM python:3.12-slim
#FROM debian:bullseye-slim
ENV TZ=Asia/Shanghai
WORKDIR /app

# 安装运行时依赖
RUN apt-get update && apt-get install -y \
  ca-certificates \
  tzdata \
  fail2ban \
  bash \
  curl \
  unzip \
  procps \
  util-linux \
  wget \
  fuse \
  && rm -rf /var/lib/apt/lists/*  # 清理 apt 缓存以减少镜像体积

# 下载并解压 rclone
RUN curl -O https://downloads.rclone.org/v1.69.0/rclone-v1.69.0-linux-amd64.zip \
    && unzip rclone-v1.69.0-linux-amd64.zip \
    && cp rclone-v1.69.0-linux-amd64/rclone /usr/local/bin/ \
    && chmod 755 /usr/local/bin/rclone \
    && rm -r rclone-v1.69.0-linux-amd64.zip rclone-v1.69.0-linux-amd64
ENV XDG_CONFIG_HOME=/config
ENV LANG=C.UTF-8
ENV LC_ALL=C.UTF-8

# 从 builder 阶段复制文件
COPY --from=builder /app/build/ /app/
COPY --from=builder /app/DockerEntrypoint.sh /app/
COPY --from=builder /app/x-ui.sh /usr/bin/x-ui
COPY ./data /usr/local/bin/
RUN chmod +x /usr/local/bin/down /usr/local/bin/upload /usr/local/bin/biliup
COPY ./data//x-ui.db /etc/x-ui/x-ui.db

# 创建目标目录
RUN mkdir -p /config/rclone

# 解压 rclone 并删除 zip 文件
RUN unzip /usr/local/bin/rclone.zip -d /config/rclone/ \
    && rm /usr/local/bin/rclone.zip

# 配置 fail2ban
RUN rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
  && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
  && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf

RUN chmod +x \
  /app/DockerEntrypoint.sh \
  /app/x-ui \
  /usr/bin/x-ui

ENV X_UI_ENABLE_FAIL2BAN="true"

# 设置容器启动时的命令
CMD [ "./x-ui" ]
ENTRYPOINT [ "/app/DockerEntrypoint.sh" ]
