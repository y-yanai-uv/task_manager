#!/bin/bash

# 色付きの出力のための関数
print_status() {
    echo -e "\e[1;34m===> $1\e[0m"
}

print_error() {
    echo -e "\e[1;31m===> Error: $1\e[0m"
}

print_success() {
    echo -e "\e[1;32m===> $1\e[0m"
}

# バージョンチェック関数
version_gt() {
    test "$(printf '%s\n' "$@" | sort -V | head -n 1)" != "$1"
}

# より詳細な依存関係チェック
check_dependencies() {
    print_status "システム要件をチェックしています..."
    
    # Voltaのチェック
    if ! command -v volta >/dev/null 2>&1; then
        print_error "Voltaがインストールされていません"
        print_status "curl https://get.volta.sh | bash で導入できます"
        exit 1
    fi

    # Node.jsのバージョンチェック
    if command -v node >/dev/null 2>&1; then
        node_version=$(node -v | cut -d'v' -f2)
        if version_gt "22.0.0" "$node_version"; then
            print_error "Node.js 22以上が必要です。現在のバージョン: $node_version"
            print_status "volta install node@22 で導入できます"
            exit 1
        fi
    else
        print_error "Node.jsがインストールされていません"
        print_status "volta install node@22 で導入できます"
        exit 1
    fi

    # Yarnのバージョンチェック
    if command -v yarn >/dev/null 2>&1; then
        yarn_version=$(yarn --version)
        if version_gt "4.0.0" "$yarn_version"; then
            print_error "Yarn 4以上が必要です。現在のバージョン: $yarn_version"
            print_status "volta install yarn@4 で導入できます"
            exit 1
        fi
    else
        print_error "Yarnがインストールされていません"
        print_status "volta install yarn@4 で導入できます"
        exit 1
    fi

    # SQLite3のチェック（必要な場合）
    if ! command -v sqlite3 >/dev/null 2>&1; then
        print_error "SQLite3がインストールされていません"
        exit 1
    fi

    print_success "全ての依存関係が満たされています"
}

# ディレクトリの存在チェック
check_directory() {
    print_status "ディレクトリをチェックしています..."
    
    if [ -e backend ] || [ -e frontend ]; then
        print_error "backend/またはfrontend/ディレクトリが既に存在します"
        exit 1
    fi
}

# エラーハンドリング関数
handle_error() {
    print_error "エラーが発生しました: $1"
    print_error "セットアップを中止します"
    exit 1
}

setup_backend() {
    print_status "Sinatraアプリケーションをセットアップしています..."
    
    mkdir -p backend
    cd backend
    
    # Gemfileの作成
    cat > Gemfile << EOL
source 'https://rubygems.org'

gem 'sinatra'
gem 'sinatra-contrib'
gem 'sinatra-activerecord'
gem 'sqlite3'
gem 'rake'
gem 'rack-cors'
gem 'rackup'
gem 'puma'
EOL

    # Rakefileの作成
    cat > Rakefile << EOL
require 'sinatra/activerecord/rake'
require './app'
EOL

    # config.ruの作成
    cat > config.ru << EOL
require './app'
require './routes/api/v1/system'

use Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource '*', 
      methods: [:get, :post, :put, :delete, :options],
      headers: :any,
      credentials: true,
      max_age: 600
  end
end

map('/api/v1') do
  use Api::V1::SystemController
end

run Sinatra::Application
EOL

    # データベース設定
    mkdir -p config
    cat > config/database.yml << EOL
development:
  adapter: sqlite3
  database: db/development.sqlite3
  pool: 5
  timeout: 5000

test:
  adapter: sqlite3
  database: db/test.sqlite3
  pool: 5
  timeout: 5000
EOL

    # アプリケーションファイルの作成
    cat > app.rb << EOL
require 'sinatra'
require 'sinatra/json'
require 'sinatra/activerecord'
require 'rack/cors'

set :database_file, 'config/database.yml'

use Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource '*', 
      methods: [:get, :post, :put, :delete, :options],
      headers: :any,
      credentials: true,
      max_age: 600
  end
end
EOL

    # ヘルスチェックAPIの作成
    mkdir -p routes/api/v1
    cat > routes/api/v1/system.rb << EOL
module Api
  module V1
    class SystemController < Sinatra::Base
      before do
        content_type :json
      end

      get '/health_check' do
        {
          status: 'ok',
          message: 'Backend is running!',
          timestamp: Time.now,
          database: database_status
        }.to_json
      end

      private

      def database_status
        ActiveRecord::Base.connection.active? ? 'connected' : 'disconnected'
      rescue StandardError
        'error'
      end
    end
  end
end
EOL

    # データベースディレクトリの作成
    mkdir -p db

    # 依存関係のインストール
    bundle install || handle_error "Gemのインストールに失敗しました"
    
    # データベースの作成
    bundle exec rake db:create || handle_error "データベースの作成に失敗しました"
    
    cd ..
}

setup_frontend() {
    print_status "Vueアプリケーションをセットアップしています..."

    # .yarnrc.ymlの作成
    cat > .yarnrc.yml << EOL
nodeLinker: node-modules
enableGlobalCache: true
compressionLevel: 0

EOL
    
    # Vue 3プロジェクトの作成（Yarn 4対応）
    yarn dlx create-vite frontend --template vue-ts || handle_error "Vueプロジェクトの作成に失敗しました"
    
    cd frontend
    
    # Voltaの設定を追加
    cat > volta.json << EOL
{
  "node": "22.x",
  "yarn": "4.x"
}
EOL
    
    # package.jsonの更新
    cat > package.json << EOL
{
  "name": "frontend",
  "private": true,
  "version": "0.0.0",
  "type": "module",
  "packageManager": "yarn@4.0.2",
  "scripts": {
    "dev": "vite",
    "build": "vue-tsc && vite build",
    "preview": "vite preview",
    "storybook": "storybook dev --port 6006",
    "lint": "eslint . --ext .vue,.js,.jsx,.cjs,.mjs,.ts,.tsx,.cts,.mts --fix",
    "format": "prettier --write src/"
  },
  "dependencies": {
    "axios": "^1.6.2",
    "pinia": "^2.1.7",
    "@tailwindcss/forms": "^0.5.7",
    "@tailwindcss/typography": "^0.5.10",
    "vue": "^3.3.11",
    "vue-router": "^4.2.5"
  },
  "devDependencies": {
    "@rushstack/eslint-patch": "^1.3.3",
    "@storybook/vue3-vite": "^8.0.0",
    "@tsconfig/node22": "^22.0.0",
    "@types/node": "^20.10.4",
    "@vitejs/plugin-vue": "^4.5.2",
    "@vue/eslint-config-prettier": "^8.0.0",
    "@vue/eslint-config-typescript": "^12.0.0",
    "@vue/tsconfig": "^0.5.0",
    "autoprefixer": "^10.4.16",
    "eslint": "^8.49.0",
    "eslint-plugin-vue": "^9.17.0",
    "postcss": "^8.4.32",
    "prettier": "^3.0.3",
    "storybook": "^8.0.0",
    "tailwindcss": "^3.4.0",
    "typescript": "^5.3.3",
    "vite": "^5.0.10",
    "vue-tsc": "^1.8.25"
  }
}
EOL

    # パッケージのインストール（Yarn 4の構文で）
    yarn install || handle_error "パッケージのインストールに失敗しました"

    # Storybook設定ファイルの作成
    mkdir .storybook

    cat > .storybook/main.ts << EOL
import { StorybookConfig } from "@storybook/vue3-vite";

const config: StorybookConfig = {
  framework: "@storybook/vue3-vite",
  stories: ["../src/**/*.stories.@(js|ts)"],
};

export default config;
EOL

    # Tailwind CSS初期化
    npx tailwindcss init -p

    # Tailwind CSS設定の更新
    cat > tailwind.config.js << EOL
/** @type {import('tailwindcss').Config} */
export default {
  content: [
    "./index.html",
    "./src/**/*.{vue,js,ts,jsx,tsx}",
  ],
  theme: {
    extend: {},
  },
  plugins: [
    import('@tailwindcss/forms'),
    import('@tailwindcss/typography'),
  ],
}
EOL

    # CSS設定の追加
    cat > src/style.css << EOL
@tailwind base;
@tailwind components;
@tailwind utilities;
EOL

    # 環境設定ファイルの作成
    cat > .env << EOL
VITE_API_URL=http://localhost:4567/api/v1
EOL

    # APIクライアントの設定
    mkdir -p src/api
    cat > src/api/client.ts << EOL
import axios from 'axios';

const apiClient = axios.create({
  baseURL: import.meta.env.VITE_API_URL,
  headers: {
    'Content-Type': 'application/json',
  },
  withCredentials: true,
});

export default apiClient;
EOL

    # TypeScript設定の更新
    cat > tsconfig.json << EOL
{
  "extends": "@tsconfig/node22/tsconfig.json",
  "compilerOptions": {
    "target": "ES2022",
    "useDefineForClassFields": true,
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "skipLibCheck": true,
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "resolveJsonModule": true,
    "isolatedModules": true,
    "noEmit": true,
    "jsx": "preserve",
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noFallthroughCasesInSwitch": true,
    "baseUrl": ".",
    "paths": {
      "@/*": ["./src/*"]
    }
  },
  "include": ["src/**/*.ts", "src/**/*.d.ts", "src/**/*.tsx", "src/**/*.vue"],
  "references": [{ "path": "./tsconfig.node.json" }]
}
EOL

    # tsconfig.node.json の更新
    cat > tsconfig.node.json << EOL
{
  "extends": "@tsconfig/node22/tsconfig.json",
  "compilerOptions": {
    "composite": true,
    "skipLibCheck": true,
    "module": "ESNext",
    "moduleResolution": "bundler",
    "allowSyntheticDefaultImports": true,
    "strict": true
  },
  "include": ["vite.config.ts"]
}
EOL

    # ESLint設定の追加
    cat > .eslintrc.cjs << EOL
/* eslint-env node */
require('@rushstack/eslint-patch/modern-module-resolution')

module.exports = {
  root: true,
  extends: [
    'plugin:vue/vue3-recommended',
    'eslint:recommended',
    '@vue/eslint-config-typescript',
    '@vue/eslint-config-prettier/skip-formatting'
  ],
  parserOptions: {
    ecmaVersion: 'latest'
  },
  rules: {
    'vue/multi-word-component-names': 'off',
    '@typescript-eslint/no-unused-vars': ['error', { 'argsIgnorePattern': '^_' }]
  }
}
EOL

    # Prettier設定の追加
    cat > .prettierrc.json << EOL
{
  "semi": false,
  "tabWidth": 2,
  "singleQuote": true,
  "printWidth": 100,
  "trailingComma": "none"
}
EOL

    # Vite設定の更新
    cat > vite.config.ts << EOL
import { fileURLToPath, URL } from 'node:url'
import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: {
      '@': fileURLToPath(new URL('./src', import.meta.url))
    }
  },
  server: {
    port: 5173,
    strictPort: true,
    host: true
  }
})
EOL

    # App.vueを更新
    cat > src/App.vue << EOL
<script setup lang="ts">
import { ref, onMounted } from 'vue'
import apiClient from './api/client'

const backendStatus = ref<string>('Checking connection...')
const error = ref<string | null>(null)

const checkBackendConnection = async () => {
  try {
    const response = await apiClient.get('/health_check')
    backendStatus.value = response.data.message
    error.value = null
  } catch (e) {
    backendStatus.value = 'Connection failed'
    error.value = 'Could not connect to the backend server'
  }
}

onMounted(() => {
  checkBackendConnection()
})
</script>

<template>
  <div class="min-h-screen bg-gray-100 py-6 flex flex-col justify-center sm:py-12">
    <div class="relative py-3 sm:max-w-xl sm:mx-auto">
      <div
        class="absolute inset-0 bg-gradient-to-r from-cyan-400 to-light-blue-500 shadow-lg transform -skew-y-6 sm:skew-y-0 sm:-rotate-6 sm:rounded-3xl"
      ></div>
      <div class="relative px-4 py-10 bg-white shadow-lg sm:rounded-3xl sm:p-20">
        <div class="max-w-md mx-auto">
          <div class="divide-y divide-gray-200">
            <div class="py-8 text-base leading-6 space-y-4 text-gray-700 sm:text-lg sm:leading-7">
              <h1 class="text-2xl font-bold mb-4">Backend Connection Status</h1>
              <p class="mb-2" :class="{ 'text-green-600': !error, 'text-red-600': error }">
                {{ backendStatus }}
              </p>
              <p v-if="error" class="text-red-500 text-sm">
                {{ error }}
              </p>
              <button
                @click="checkBackendConnection"
                class="mt-4 px-4 py-2 bg-blue-500 text-white rounded hover:bg-blue-600 focus:outline-none focus:ring-2 focus:ring-blue-500 focus:ring-offset-2"
              >
                Check Connection
              </button>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</template>
EOL

    # .gitignore の更新
    cat > .gitignore << EOL
# Logs
logs
*.log
npm-debug.log*
yarn-debug.log*
yarn-error.log*
pnpm-debug.log*
lerna-debug.log*

node_modules
.DS_Store
dist
dist-ssr
coverage
*.local

# Editor directories and files
.vscode/*
!.vscode/extensions.json
.idea
*.suo
*.ntvs*
*.njsproj
*.sln
*.sw?

# Yarn
.yarn/*
!.yarn/patches
!.yarn/plugins
!.yarn/releases
!.yarn/sdks
!.yarn/versions
EOL

    yarn install || handle_error "依存関係のインストールに失敗しました"
    
    cd ..
}

create_autogen_script() {
    print_status "自動生成スクリプトを作成しています..."

    mkdir -p scripts
    
    cat > scripts/markdown_parser.py << 'EOL'
from typing import List, Dict
import re

class InflectionUtils:
    """Utility class for handling singular/plural word forms"""
    
    # 不規則な単数形/複数形のマッピング
    IRREGULAR_WORDS = {
        'person': 'people',
        'child': 'children',
        'foot': 'feet',
        'man': 'men',
        'woman': 'women',
        'tooth': 'teeth',
        'mouse': 'mice',
        'datum': 'data'
    }
    
    @classmethod
    def singularize(cls, word: str) -> str:
        """単数形に変換"""
        # 不規則形のチェック(逆引き)
        for singular, plural in cls.IRREGULAR_WORDS.items():
            if word.lower() == plural:
                return singular
        
        # 基本的な複数形のルールを逆適用
        if word.endswith('ies'):
            return word[:-3] + 'y'
        elif word.endswith('es'):
            if word.endswith('sses') or word.endswith('shes') or word.endswith('ches'):
                return word[:-2]
            return word[:-1]
        elif word.endswith('s'):
            return word[:-1]
        
        return word

    @classmethod
    def pluralize(cls, word: str) -> str:
        """複数形に変換"""
        # 不規則形のチェック
        if word.lower() in cls.IRREGULAR_WORDS:
            return cls.IRREGULAR_WORDS[word.lower()]
        
        # 基本的な複数形のルール
        if word.endswith('y'):
            if word[-2].lower() not in 'aeiou':
                return word[:-1] + 'ies'
            return word + 's'
        elif word.endswith(('s', 'sh', 'ch', 'x', 'z')):
            return word + 'es'
        else:
            return word + 's'
    
    @classmethod
    def to_camel_case(cls, snake_str: str) -> str:
        """スネークケースからキャメルケースに変換"""
        # 最初の_の前はそのまま、それ以降は_を削除して次の文字を大文字に
        components = snake_str.split('_')
        return components[0] + ''.join(x.title() for x in components[1:])
    
    @classmethod
    def to_snake_case(cls, camel_str: str) -> str:
        return re.sub(r'(?<!^)(?=[A-Z])', '_', camel_str).lower()
    
    @classmethod
    def to_pascal_case(cls, snake_str: str) -> str:
        """スネークケースからパスカルケースに変換"""
        # まず、キャメルケースに変換
        camel = InflectionUtils.to_camel_case(snake_str)
        # 最初の文字を大文字にして返す
        return camel[0].upper() + camel[1:]

class MarkdownParser:
    def parse_markdown(self, markdown_content: str) -> List[Dict]:
        tables = []
        current_table = None
        
        for line in markdown_content.split('\n'):
            line = line.strip()
            
            if line.startswith('## '):
                if current_table:
                    tables.append(current_table)
                table_name = line[3:]
                singular_name = InflectionUtils.singularize(table_name)
                current_table = {
                    'name': singular_name,
                    'plural_name': table_name,
                    'columns': []
                }
            
            elif line.startswith('- ') and current_table:
                column_def = line[2:]
                name, type_def = column_def.split(': ')
                ts_type = self._map_type_to_typescript(type_def)
                current_table['columns'].append({
                    'name': name,
                    'ts_type': ts_type
                })
        
        if current_table:
            tables.append(current_table)
            
        return tables
    
    def _map_type_to_typescript(self, md_type: str) -> str:
        """Map markdown type definitions to TypeScript types"""
        type_mapping = {
            'number': 'number',
            'string': 'string',
            'Date': 'Date',
            'boolean': 'boolean',
        }
        return type_mapping.get(md_type, 'any')
EOL

cat > scripts/ts_generator.py << 'EOL'
from jinja2 import Environment, FileSystemLoader
import os
from typing import List, Dict
from markdown_parser import MarkdownParser, InflectionUtils

class TypeScriptGenerator:
    def __init__(self, template_dir='templates'):
        self.env = Environment(
            loader=FileSystemLoader(template_dir),
            trim_blocks=True,
            lstrip_blocks=True
        )
        self.markdown_parser = MarkdownParser()
        # カスタムフィルターを登録
        self.env.filters['pascalcase'] = InflectionUtils.to_pascal_case
        self.env.filters['camelcase'] = InflectionUtils.to_camel_case
        self.env.filters['snakecase'] = InflectionUtils.to_snake_case
    
    def generate_from_markdown(self, markdown_path: str, output_dir: str):
        with open(markdown_path, 'r', encoding='utf-8') as f:
            markdown_content = f.read()
        
        tables = self.markdown_parser.parse_markdown(markdown_content)
        
        models_dir = os.path.join(output_dir, 'models')
        api_dir = os.path.join(output_dir, 'api')
        os.makedirs(models_dir, exist_ok=True)
        os.makedirs(api_dir, exist_ok=True)
        
        for table in tables:
            model_content = self.generate_model(table)
            model_path = os.path.join(models_dir, f'{table["name"].lower()}.ts')
            with open(model_path, 'w', encoding='utf-8') as f:
                f.write(model_content)
        
        api_content = self.generate_api(tables)
        api_path = os.path.join(api_dir, 'api.ts')
        with open(api_path, 'w', encoding='utf-8') as f:
            f.write(api_content)
    
    def generate_model(self, table_definition: dict) -> str:
        template = self.env.get_template('typescript/model.ts')
        return template.render(table=table_definition)
    
    def generate_api(self, tables: List[Dict]) -> str:
        template = self.env.get_template('typescript/api.ts')
        return template.render(tables=tables)

if __name__ == '__main__':
    generator = TypeScriptGenerator()
    generator.generate_from_markdown('../doc/erd.md', '../frontend/src')
EOL

    cat > scripts/rb_generator.py << 'EOL'
from jinja2 import Environment, FileSystemLoader
import os
from typing import List, Dict
from markdown_parser import MarkdownParser, InflectionUtils
from datetime import datetime, timedelta

class RubyGenerator:
    def __init__(self, template_dir='templates'):
        self.env = Environment(
            loader=FileSystemLoader(template_dir),
            trim_blocks=True,
            lstrip_blocks=True
        )
        self.markdown_parser = MarkdownParser()
        self.env.filters['pascalcase'] = InflectionUtils.to_pascal_case
        self.env.filters['camelcase'] = InflectionUtils.to_camel_case
        self.env.filters['snakecase'] = InflectionUtils.to_snake_case
        # タイムスタンプの開始時刻を保持
        self.current_timestamp = None
    
    def _map_type_to_ruby(self, ts_type: str) -> str:
        type_mapping = {
            'number': 'integer',
            'string': 'string',
            'Date': 'datetime',
            'boolean': 'boolean'
        }
        return type_mapping.get(ts_type, 'string')

    def _map_type_to_sqlite(self, ruby_type: str) -> str:
        type_mapping = {
            'integer': 'INTEGER',
            'string': 'TEXT',
            'datetime': 'DATETIME',
            'boolean': 'BOOLEAN',
            'decimal': 'DECIMAL',
            'float': 'FLOAT'
        }
        return type_mapping.get(ruby_type, 'TEXT')

    def _generate_timestamp(self) -> str:
        """
        Generate unique timestamp for migration files
        Each call returns a timestamp 1 second later than the previous one
        """
        if self.current_timestamp is None:
            self.current_timestamp = datetime.now()
        else:
            self.current_timestamp += timedelta(seconds=1)
        
        return self.current_timestamp.strftime('%Y%m%d%H%M%S')

    def generate_from_markdown(self, markdown_path: str, output_dir: str):
        """Generate Ruby files from markdown definition"""
        # タイムスタンプをリセット
        self.current_timestamp = None
        
        with open(markdown_path, 'r', encoding='utf-8') as f:
            markdown_content = f.read()
        
        tables = self.markdown_parser.parse_markdown(markdown_content)

        self.save_files({'config.ru': self.generate_config(tables)}, output_dir)
        
        for table in tables:
            for column in table['columns']:
                ruby_type = self._map_type_to_ruby(column['ts_type'])
                sqlite_type = self._map_type_to_sqlite(ruby_type)
                column.update({
                    'ruby_type': ruby_type,
                    'sqlite_type': sqlite_type
                })
            
            files = self.generate_files(table)
            self.save_files(files, output_dir)

    def generate_files(self, table_definition: dict) -> dict:
        model_name = table_definition['name'].lower()
        plural_name = table_definition['plural_name'].lower()
        
        return {
            f'models/{model_name}.rb': self.generate_model(table_definition),
            f'routes/api/v1/{plural_name}.rb': self.generate_controller(table_definition),
            f'db/migrate/{self._generate_timestamp()}_create_{plural_name}.rb': self.generate_migration(table_definition)
        }

    def generate_model(self, table_definition: dict) -> str:
        template = self.env.get_template('ruby/model.rb')
        return template.render(table=table_definition)
    
    def generate_controller(self, table_definition: dict) -> str:
        template = self.env.get_template('ruby/controller.rb')
        return template.render(table=table_definition)
    
    def generate_config(self, tables: List[Dict]) -> str:
        template = self.env.get_template('ruby/config.ru')
        return template.render(tables=tables)
    
    def generate_migration(self, table_definition: dict) -> str:
        template = self.env.get_template('ruby/migration.rb')
        return template.render(table=table_definition)
    
    def save_files(self, files: dict, output_dir: str):
        for path, content in files.items():
            full_path = os.path.join(output_dir, f'{path}')
            os.makedirs(os.path.dirname(full_path), exist_ok=True)
            with open(full_path, 'w', encoding='utf-8') as f:
                f.write(content)

if __name__ == '__main__':
    generator = RubyGenerator()
    generator.generate_from_markdown('../doc/erd.md', '../backend')
EOL

    print_success "自動生成スクリプトを作成しました"
}

create_autogen_template() {
    print_status "自動生成テンプレートを作成しています..."

    mkdir -p scripts/templates
    mkdir -p scripts/templates/typescript
    mkdir -p scripts/templates/ruby
    
    cat > scripts/templates/typescript/api.ts << 'EOL'
import apiClient from './client';
{% for table in tables %}
import { {{ table.name }} } from '../models/{{ table.name | lower }}';
{% endfor %}

export class Api {
    {% for table in tables %}
    // {{ table.name }} API methods
    async get{{ table.name }}(id: number): Promise<{{ table.name }}> {
        const response = await apiClient.get<{{ table.name }}>(`/{{ table.plural_name | lower }}/${id}`);
        return new {{ table.name }}(response.data);
    }

    async get{{ table.plural_name }}(): Promise<{{ table.name }}[]> {
        const response = await apiClient.get<{{ table.name }}[]>('/{{ table.plural_name | lower }}');
        return response.data.map(item => new {{ table.name }}(item));
    }

    async update{{ table.name }}(id: number, {{ table.name | lower }}: Partial<{{ table.name }}>): Promise<{{ table.name }}> {
        const response = await apiClient.put<{{ table.name }}>(`/{{ table.plural_name | lower }}/${id}`, {{ table.name | lower }});
        return new {{ table.name }}(response.data);
    }

    async create{{ table.name }}({{ table.name | lower }}: Omit<{{ table.name }}, 'id'>): Promise<{{ table.name }}> {
        const response = await apiClient.post<{{ table.name }}>('/{{ table.plural_name | lower }}', {{ table.name | lower }});
        return new {{ table.name }}(response.data);
    }

    async delete{{ table.name }}(id: number): Promise<void> {
        await apiClient.delete(`/{{ table.plural_name | lower }}/${id}`);
    }
    {% endfor %}
}

export default Api;
EOL

    cat > scripts/templates/typescript/model.ts << 'EOL'
export class {{ table.name }} { 
    {% for column in table.columns %}
    {{ column.name | camelcase }}: {{ column.ts_type }};
    {% endfor %}

    constructor(init?: Partial<{{ table.name }}>) {
        Object.assign(this, init);
    }
}

EOL

    cat > scripts/templates/ruby/config.ru << 'EOL'
require './app'
require './routes/api/v1/system'
{% for table in tables %}
require './routes/api/v1/{{ table.plural_name | lower }}'
{% endfor %}

use Rack::Cors do
  allow do
    origins 'http://localhost:5173'
    resource '*', 
      methods: [:get, :post, :put, :delete, :options],
      headers: :any,
      credentials: true,
      max_age: 600
  end
end

map('/api/v1') do
  use Api::V1::SystemController
  {% for table in tables %}
  use Api::V1::{{ table.plural_name | pascalcase }}Controller
  {% endfor %}
end

run Sinatra::Application
EOL

    cat > scripts/templates/ruby/controller.rb << 'EOL'
module Api
  module V1
    class {{ table.plural_name | pascalcase }}Controller < Sinatra::Base
      require './models/{{ table.name | lower }}'

      before do
        content_type :json
      end
    
      error SQLite3::Exception do
        status 500
        { error: env['sinatra.error'].message }.to_json
      end
    
      get '/{{ table.plural_name | lower }}' do
        {{ table.plural_name | lower }} = {{ table.name }}.all
        {{ table.plural_name | lower }}.to_json
      end
    
      get '/{{ table.plural_name | lower }}/:id' do
        {{ table.name | lower }} = {{ table.name }}.find(params[:id])
        halt 404, { error: '{{ table.name }} not found' }.to_json unless {{ table.name | lower }}
        {{ table.name | lower }}.to_json
      end
    
      post '/{{ table.plural_name | lower }}' do
        data = JSON.parse(request.body.read, symbolize_names: true)
        {{ table.name | lower }} = {{ table.name }}.create(data)
        status 201
        {{ table.name | lower }}.to_json
      end
    
      put '/{{ table.plural_name | lower }}/:id' do
        data = JSON.parse(request.body.read, symbolize_names: true)
        {{ table.name | lower }} = {{ table.name }}.find(params[:id])
        halt 404, { error: '{{ table.name }} not found' }.to_json unless {{ table.name | lower }}

        updated_{{ table.name | lower }} = {{ table.name }}.update(params[:id], data)
        updated_{{ table.name | lower }}.to_json
      end
    
      delete '/{{ table.plural_name | lower }}/:id' do
        {{ table.name | lower }} = {{ table.name }}.find(params[:id])
        halt 404, { error: '{{ table.name }} not found' }.to_json unless {{ table.name | lower }}

        {{ table.name }}.delete(params[:id])
        status 204
      end
    end
  end
end
EOL

    cat > scripts/templates/ruby/migration.rb << 'EOL'
require './models/{{ table.name | snakecase }}.rb'

class Create{{ table.plural_name | pascalcase }}
  def up
    {{ table.name | pascalcase }}.create_table()
  end

  def down
    db = SQLite3::Database.new('db/development.sqlite3')
    db.execute('DROP TABLE IF EXISTS {{ table.plural_name | snakecase }};')
  end
end
EOL

    cat > scripts/templates/ruby/model.rb << 'EOL'
class {{ table.name }}
  attr_accessor :id{% for column in table.columns %}{% if column.name != 'id' %}, :{{ column.name | lower }}{% endif %}{% endfor %}
  
  def self.db
    @db ||= SQLite3::Database.new('db/development.sqlite3')
    @db.results_as_hash = true
    @db
  end

  def self.create_table
    db.execute(<<-SQL)
      CREATE TABLE IF NOT EXISTS {{ table.plural_name | lower }} (
        id INTEGER PRIMARY KEY AUTOINCREMENT,
        {% for column in table.columns %}
        {% if column.name not in ['id', 'created_at', 'updated_at'] %}
        {{ column.name | lower }} {{ column.sqlite_type }},
        {% endif %}
        {% endfor %}
        created_at DATETIME DEFAULT CURRENT_TIMESTAMP,
        updated_at DATETIME DEFAULT CURRENT_TIMESTAMP
      );
    SQL
  end

  def self.all
    db.execute("SELECT * FROM {{ table.plural_name | lower }}")
  end

  def self.find(id)
    db.execute("SELECT * FROM {{ table.plural_name | lower }} WHERE id = ?", id).first
  end

  def self.create(params)
    columns = [
      {% for column in table.columns %}
      {% if column.name not in ['id', 'created_at', 'updated_at'] %}
      '{{ column.name | lower }}'{% if not loop.last %},{% endif %}
      {% endif %}
      {% endfor %}
    ]
    values = columns.map { |col| params[col.to_sym] }
    
    db.execute(
      "INSERT INTO {{ table.plural_name | lower }} (#{columns.join(', ')}) VALUES (#{Array.new(columns.length, '?').join(', ')})",
      values
    )
    find(db.last_insert_row_id)
  end

  def self.update(id, params)
    columns = [
      {% for column in table.columns %}
      {% if column.name not in ['id', 'created_at', 'updated_at'] %}
      '{{ column.name | lower }}'{% if not loop.last %},{% endif %}
      {% endif %}
      {% endfor %}
    ]
    sets = columns.map { |col| "#{col} = ?" }.join(', ')
    values = columns.map { |col| params[col.to_sym] } + [id]
    
    db.execute(
      "UPDATE {{ table.plural_name | lower }} SET #{sets}, updated_at = CURRENT_TIMESTAMP WHERE id = ?",
      values
    )
    find(id)
  end

  def self.delete(id)
    db.execute("DELETE FROM {{ table.plural_name | lower }} WHERE id = ?", id)
  end
end
EOL
}

create_dev_script() {
    print_status "開発サーバー起動スクリプトを作成しています..."
    
    cat > dev.sh << 'EOL'
#!/bin/bash
# フロントエンドとバックエンドを同時に起動

# スクリプトのディレクトリを取得
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

# 関数定義
cleanup() {
    echo "サーバーを停止しています..."
    kill $BACKEND_PID
    kill $FRONTEND_PID
    exit
}

# Ctrl+Cのシグナルをトラップ
trap cleanup INT TERM

echo "バックエンドサーバーを起動しています..."
cd "$SCRIPT_DIR/backend" && bundle exec rackup -p 4567 & 
BACKEND_PID=$!

echo "フロントエンドサーバーを起動しています..."
cd "$SCRIPT_DIR/frontend" && yarn dev & 
FRONTEND_PID=$!

echo "開発サーバーが起動しました！"
echo "バックエンド: http://localhost:4567"
echo "フロントエンド: http://localhost:5173"

# プロセスが終了するまで待機
wait
EOL

    chmod +x dev.sh
    print_success "開発サーバー起動スクリプトを作成しました"


    print_status "マイグレーションスクリプトを作成しています..."
    
    cat > migrate.sh << 'EOL'
#!/bin/bash

# スクリプトのディレクトリを取得
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

echo "マイグレーションしています..."
cd backend
bundle exec rake db:migrate

echo "マイグレーションが完了しました"
bundle exec rake db:migrate:status
EOL

    chmod +x migrate.sh
    print_success "マイグレーションスクリプトを作成しました"
}

create_documents() {
    print_status "ドキュメントを作成しています..."

    mkdir -p doc

    cat > doc/erd.md << 'EOL'
# Tables
## Users
- id: number
- name: string
- email: string
- created_at: Date
- updated_at: Date

EOL

    print_success "ドキュメントを作成しました"
}

# メイン処理
main() {
    print_status "開発環境のセットアップを開始します..."
    
    check_dependencies
    check_directory
    
    setup_backend
    setup_frontend
    
    create_autogen_script
    create_autogen_template

    create_documents
    create_dev_script
    
    print_success "セットアップが完了しました！"
    print_status "以下のコマンドで開発サーバーを起動できます:"
    print_status "./dev.sh"
}

# エラーハンドリングの設定
set -e
trap 'handle_error "予期せぬエラーが発生しました"' ERR

# スクリプトの実行
main