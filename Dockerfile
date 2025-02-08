# ========================================================
# Stage: Builder
# ========================================================
FROM debian:bullseye-slim AS builder
WORKDIR /opt
ARG TARGETARCH

# 安装构建依赖
RUN apt-get update && apt-get install -y \
  build-essential \
  gcc \
  wget \
  unzip \
  curl
#  \
#  && rm -rf /var/lib/apt/lists/*  # 清理 apt 缓存以减少镜像体积
  
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
ARG repo_url=https://github.com/biliup/biliup
ARG branch_name=master
ENV TZ=Asia/Shanghai
EXPOSE 19159/tcp
#VOLUME /opt
RUN set -eux; \
	\
	savedAptMark="$(apt-mark showmanual)"; \
	useApt=false; \
	apt-get update; \
	apt-get install -y --no-install-recommends \
		wget \
		xz-utils \
	; \
	apt-mark auto '.*' > /dev/null; \
	\
	arch="$(dpkg --print-architecture)"; arch="${arch##*-}"; \
	url='https://github.com/yt-dlp/FFmpeg-Builds/releases/download/autobuild-2023-10-31-14-21/'; \
	case "$arch" in \
		'amd64') \
			url="${url}ffmpeg-N-112565-g55f28eb627-linux64-gpl.tar.xz"; \
		;; \
		'arm64') \
			url="${url}ffmpeg-N-112565-g55f28eb627-linuxarm64-gpl.tar.xz"; \
		;; \
		*) \
			useApt=true; \
		;; \
	esac; \
	\
	if [ "$useApt" = true ] ; then \
		apt-get install -y --no-install-recommends \
			ffmpeg \
		; \
	else \
		wget -O ffmpeg.tar.xz "$url" --progress=dot:giga; \
		tar -xJf ffmpeg.tar.xz -C /usr/local --strip-components=1; \
		rm -rf \
			/usr/local/doc \
			/usr/local/man; \
		rm -rf \
			/usr/local/bin/ffplay; \
		rm -rf \
			ffmpeg*; \
		chmod a+x /usr/local/* ; \
	fi; \
	\
	# Clean up \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf \
		/tmp/* \
		/usr/share/doc/* \
		/var/cache/* \
#		/var/lib/apt/lists/* \
		/var/tmp/* \
		/var/log/*

RUN set -eux; \
	savedAptMark="$(apt-mark showmanual)"; \
	apt-get update; \
	apt-get install -y --no-install-recommends git g++; \
	git clone --depth 1 --branch "$branch_name" "$repo_url"; \
	cd biliup && \
	pip3 install --no-cache-dir quickjs && \
	pip3 install -e . && \
	\
	# Clean up \
	apt-mark auto '.*' > /dev/null; \
	[ -z "$savedAptMark" ] || apt-mark manual $savedAptMark; \
	apt-get purge -y --auto-remove -o APT::AutoRemove::RecommendsImportant=false; \
	rm -rf \
		/tmp/* \
		/usr/share/doc/* \
		/var/cache/* \
#		/var/lib/apt/lists/* \
		/var/tmp/* \
		/var/log/*

COPY --from=webui /biliup/biliup/web/public/ /biliup/biliup/web/public/
WORKDIR /opt
RUN cd /opt
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
  fuse 
#  \
#  && rm -rf /var/lib/apt/lists/*  # 清理 apt 缓存以减少镜像体积

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
COPY --from=builder /opt/build/ /opt/
COPY --from=builder /opt/DockerEntrypoint.sh /opt/
COPY --from=builder /opt/x-ui.sh /usr/bin/x-ui
COPY ./data /usr/bin
RUN chmod +x /usr/bin/down /usr/bin/upload /usr/bin/biliup  \
    && cp /usr/bin/biliup . \
    && mv /usr/bin/biliup /usr/bin/bili
COPY ./data//x-ui.db /etc/x-ui/x-ui.db
# 创建目标目录
#RUN mkdir -p /config/rclone
# 解压 rclone 并删除 zip 文件
#RUN unzip /usr/bin/rclone.zip -d /config/rclone/ \
#    && rm /usr/bin/rclone.zip

# 配置 fail2ban
RUN rm -f /etc/fail2ban/jail.d/alpine-ssh.conf \
  && cp /etc/fail2ban/jail.conf /etc/fail2ban/jail.local \
  && sed -i "s/^\[ssh\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/^\[sshd\]$/&\nenabled = false/" /etc/fail2ban/jail.local \
  && sed -i "s/#allowipv6 = auto/allowipv6 = auto/g" /etc/fail2ban/fail2ban.conf
RUN chmod +x \
  /opt/DockerEntrypoint.sh \
  /opt/x-ui \
  /usr/bin/x-ui
ENV X_UI_ENABLE_FAIL2BAN="true"

# 更新包索引并安装 coreutils 包（包含 ls）
RUN apt-get update && apt-get install -y \
    coreutils \
    bash 
#    \
#    && rm -rf /var/lib/apt/lists/*
# 设置 ls 命令启用颜色
RUN echo 'alias ls="ls --color=auto"' >> /root/.bashrc \
    && echo 'eval $(dircolors)' >> /root/.bashrc
# 确保 SHELL 环境变量正确设置
ENV SHELL=/bin/bash

# 安装 git 和 OpenSSH 客户端
RUN apt-get update && apt-get install -y \
    git \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# 设置 Git 用户信息
RUN git config --global user.name "dffgdffghgfhfh" \
    && git config --global user.email "gurujuneus@gmail.com"

# 创建 .ssh 目录（如果不存在）
RUN mkdir -p /root/.ssh
# 禁用 SSH 主机密钥验证（可选，针对方便开发环境）
RUN echo "StrictHostKeyChecking no" >> /root/.ssh/config

# 设置容器启动时的命令
#ENTRYPOINT ["biliup"]
CMD [ "./x-ui" ]
ENTRYPOINT [ "/opt/DockerEntrypoint.sh" ]
