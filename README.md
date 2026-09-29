# P4ck4g3s

面向Android免解锁只读文件系统(OverlayFS)的Bionic原生工具链与pacman软件包分发体系。

## 1.项目简介

本项目是0vl0ad3r的软件包构建中心与软件源,负责:
1. **Bionic依赖库交叉编译**:在Android NDK环境下构建zstd、openssl、libarchive、libcurl、ncurses等基础库。
2. **pacman包管理器移植**:提供适用于ARM64 Bionic的原生pacman/libalpm及自举环境。
3. **常用工具链打包**:维护curl、wget、aria2、nano、vim等工具的.pkg.tar.zst标准包。
4. **自动化CI/CD与分发**:通过GitHub Actions全自动编译,生成软件源数据库(0vl0ad3r.db.tar.zst)与前端索引(index.json),支持GitHub Pages与Releases两种分发。

## 2.目录结构

```
P4ck4g3s/
├── .github/workflows/
├── bootstrap/
├── scripts/
├── output/repo/
└── README.md
```

## 3.核心规范

1. **绝对安装路径**:所有软件包统一安装至`/system/0vl0ad3r/`物理路径。
2. **RPATH隔离**:编译时注入`-Wl,-rpath,'$ORIGIN/../lib64' -Wl,--enable-new-dtags`,避免与Android系统库冲突。
3. **依赖自动推导**:库依赖通过`scripts/elfdeps.py`分析ELF的DT_NEEDED自动生成,杜绝漏写与冗余。
4. **文件归属唯一**:每个文件严格归属单一软件包(库文件归各库包,二进制归对应工具包,基础配置归base-layout)。

## 4.快速上手

### 环境要求
- Ubuntu 22.04+或Arch Linux宿主机
- Android NDK r26d(通过环境变量`ANDROID_NDK_ROOT`指定)
- 宿主工具:cmake,ninja,meson,zstd,patchelf,libalpm-dev

### 一键全量构建
```bash
export ANDROID_NDK_ROOT=/opt/android-ndk
./scripts/build-all-tools.sh
```
该命令会自动按顺序完成:
- 编译底层基础库(zlib,zstd,xz,openssl,libcurl,libarchive,ncurses,pacman)
- 切分底层动态库包
- 构建base-layout与ca-certificates
- 打包pacman自举包与常用工具集(curl,wget,aria2,nano,vim,vi)
- 更新仓库数据库索引并运行完整性门禁
- 装配客户端引导镜像(output/bootstrap/0vl0ad3r-bootstrap-aarch64.tar.zst)

### 软件包门禁校验
```bash
./scripts/verify-packages.sh
```
校验流程包括:
1. **libalpm实加载**:校验所有.pkg.tar.zst归档元数据完整性与文件冲突。
2. **index.json契约**:校验前端索引中的文件列表、size、sha256与磁盘完全一致。
3. **ELF链接闭包**:校验全局DT_NEEDED与逐包依赖覆盖率。

## 5.分发与发布

- **分支推送**:向`main`分支推送代码触发自动构建,产物发布至`gh-pages`分支。
- **版本发布**:推送`v*`标签时自动创建GitHub Release并附带所有软件包归档。
- **自定义域名**:在仓库Settings->Secrets and variables->Actions中配置`OVL0AD3R_DOMAIN`即可自动配置CNAME与镜像源列表。

## 6.开源协议

本项目基于[Apache-2.0](LICENSE)协议开源。
