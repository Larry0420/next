# 使用 Node.js 20 作為基礎
FROM node:20-bullseye

# 1. 安裝 Flutter 官方要求的系統依賴
RUN apt-get update && apt-get install -y \
    curl git unzip xz-utils zip libglu1-mesa \
    ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 2. 從 Flutter 官方 GitHub 倉庫克隆 stable 分支
RUN git clone https://github.com/flutter/flutter.git -b stable /opt/flutter

# 3. 設定環境變數（加入 npm global bin 路徑）
ENV PATH="/opt/flutter/bin:/opt/flutter/bin/cache/dart-sdk/bin:/usr/local/bin:/usr/local/lib/node_modules/@iflow-ai/iflow-cli/bin:${PATH}"


# 4. 預先初始化 Flutter
RUN flutter config --no-analytics \
    && flutter --version \
    && flutter doctor -v || true

# 5. 安裝 iFlow CLI
RUN npm install -g @iflow-ai/iflow-cli

# 6. 工作目錄與啟動
WORKDIR /app
CMD ["iflow"]
