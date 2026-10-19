# P4ck4g3s

面向Android免解锁只读文件系统(OverlayFS)的Bionic原生工具链与pacman软件包分发体系。

## 1.项目简介

本项目是0vl0ad3r的软件包构建中心与软件源,负责:
1. **Bionic依赖库交叉编译**:在Android NDK环境下构建zstd、openssl、libarchive、libcurl、ncurses等基础库。
2. **pacman包管理器移植**:提供适用于ARM64 Bionic的原生pacman/libalpm及自举环境。
3. **常用工具链打包**:维护curl、wget、aria2、nano、vim等工具的.pkg.tar.zst标准包。
4. **自动化CI/CD与分发**:通过GitHub Actions全自动编译,生成软件源数据库(0vl0ad3r.db.tar.zst)与前端索引(index.json),再由`actions/deploy-pages`部署为GitHub Pages站点。

## 2.目录结构

```
P4ck4g3s/
├── .github/workflows/
├── bootstrap/
├── scripts/
├── manifest/
├── output/repo/
└── README.md
```

## 3.核心规范

1. **绝对安装路径**:所有软件包统一安装至`/system/0vl0ad3r/`物理路径。
2. **RPATH隔离**:编译时注入`-Wl,-rpath,'$ORIGIN/../lib64' -Wl,--enable-new-dtags`,避免与Android系统库冲突。
3. **依赖自动推导**:库依赖通过`scripts/elfdeps.py`分析ELF的DT_NEEDED自动生成,杜绝漏写与冗余。
4. **文件归属唯一**:每个文件严格归属单一软件包(库文件归各库包,二进制归对应工具包,基础配置归base-layout)。
5. **版本单一来源**:`manifest/components.manifest`是所有版本号、上游地址与包描述的唯一来源,由`scripts/sync-archlinux.py`从Arch官方源生成,构建脚本经`scripts/manifest.sh`读取。清单漂移在推送/PR的CI构建前即失败(`sync-archlinux.py --check`);定时构建里这道门只告警不拦停——上游每次发版都会让它失败,若在定时构建里也硬失败,每日重建会先死在版本门上,而它的职责是接住上游tarball漂移(下载时sha256失配),那道检查在版本门之后,版本门先死就永远轮不到它。定时构建因此仍按仓库已提交的清单重建发布,版本升级继续由人审阅后提交。NDK版本与tarball sha256同样以清单为钉值,`bootstrap/env.sh`构建前实测校验。详见`manifest/README.md`。

## 4.快速上手

### 环境要求
- Ubuntu 22.04+或Arch Linux宿主机
- Android NDK r30(钉在`manifest/components.manifest`的ndk行,通过环境变量`ANDROID_NDK_ROOT`指定)
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

- **分支推送**:向`main`分支推送代码触发自动构建,产物经`actions/deploy-pages`部署到GitHub Pages站点。这是**唯一在用的软件源**,db与包作为同一棵目录树一次落下,始终自洽。
- **定时构建**:每天北京时间09:00(UTC 01:00)自动重编并重新部署。目的是接住上游tarball漂移——ncurses/nano这类上游会重新打包的产物,清单里钉死的sha256迟早失配,与其等下一次无关构建撞上,不如每日主动重编一次。上游**版本**漂移在这条里只作告警(构件`refreshed-manifest`留一份上游现状的复核材料),不拦停本次重建:发布物始终来自仓库已提交的清单,版本升级由人审阅后提交。
- **版本发布**:推送`v*`标签时自动创建GitHub Release并附带所有软件包归档,作为可复现的**版本快照**。注意该步骤与上面的站点部署互斥(前者仅在tag时触发,后者仅在非tag时触发),所以**首次打tag之前Releases是空的**。GitHub对tag推送不做`paths`过滤,所以tag必定能触发本workflow。
- **自定义域名**:已绑定<https://r3p0.orionisli.com>。DNS指向本仓库的Pages站点,与`*.github.io`同源同内容,换域名不必重新打包。在仓库Settings->Secrets and variables->Actions中配置`OVL0AD3R_DOMAIN`变量后,`publish-repo.sh`会自动写入`CNAME`并把该域名作为镜像源列表的首选地址。
  - 排查时请注意:站点内容由**最近一次`actions/deploy-pages`产物**决定,不是`gh-pages`分支。该分支自改用Actions部署后便不再更新,只作历史留存。**分支内容新、站点内容旧**曾经真实发生过,排查时先比对站点而不是分支。

### 目录布局

```
/ (pacman按Server基准取,强制平铺)
  0vl0ad3r.db -> 0vl0ad3r.db.tar.zst
  0vl0ad3r.files -> 0vl0ad3r.files.tar.zst
  index.json (客户端发现接口)
  <N个.pkg.tar.zst>
  CNAME
/bootstrap/ (非pacman资源,可自由分层)
  0vl0ad3r-bootstrap-aarch64.tar.zst
```

根目录必须平铺:libalpm拼接远端URL时,db走`db->servers`+`/<treename><ext>`(`be_sync.c:189-194`),包走`server`+`/<文件名>`(`dload.c:774`),**共用同一个`Server`基准且路径均为裸文件名**,没有"包放子目录"的配置项。因此`pool/`那类布局在apt上成立(apt从`deb`行的`uri`+component推导包路径),在pacman上不成立。

引导种子包不由pacman拉取(客户端从APK asset`app/src/main/assets/bootstrap/`读取),故可放进子目录;这里刻意与APK asset保持同一路径,维护时只需记一套。

## 6.开源协议

本项目基于[Apache-2.0](LICENSE)协议开源。
