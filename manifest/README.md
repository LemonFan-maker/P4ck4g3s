# manifest/

`components.manifest`是本仓库**版本号、上游地址与描述的唯一来源**,CSV格式,带表头。

- **不要手工编辑。**改版本或描述请改`scripts/sync-archlinux.py`里对应的组件条目,然后重新运行:

  ```bash
  ./scripts/sync-archlinux.py
  ```

- CI用`--check`校验已提交的清单与上游一致,手改会在CI上失败:

  ```bash
  ./scripts/sync-archlinux.py --check
  ```

## 字段

| 字段 | 含义 |
|---|---|
| `pkgname` | 本仓库产出的包名 |
| `kind` | `lib` / `tool` / `data` / `toolchain`(`toolchain`表示构建输入,不发布为包) |
| `source` | 版本号的权威来源,决定`--check`怎么验证这一行,见下 |
| `repo` | 上游git仓库地址;空表示不走git |
| `ref` | 上游git tag / branch,取源时钉住;空表示该组件走tarball |
| `tar` | 上游发布产物文件名,**由`version`套模板推导**,不手填 |
| `tar_url` | tarball主下载地址,同样由模板推导 |
| `sha256` | 下载产物的校验值。走tarball的行**必须**有对应版本的值,否则`--check`拒绝生成清单 |
| `arch_pkg` | 对应的Arch官方包名;空表示Arch没有对应包 |
| `version` | 本仓库实际构建的版本号,即包里的pkgver |
| `desc` | 软件包描述。取自Arch官方`pkgdesc`原文,不翻译 |

## `source`的三种取值

版本号必须有一个**唯一权威来源**,否则就会退化成"同一个值抄在三个文件里,改的时候漏一处"。`source`就是声明这一行的权威在哪里,`--check`据此决定怎么验证它:

| `source` | 权威 | `--check`行为 |
|---|---|---|
| `arch` | Arch官方源 | 重新抓取Arch `pkgver`并比对 |
| `pin` | 本仓库自己钉的输入 | 只要求非空;清单**就是**它的记录处 |
| `derived` | 某个构建输入(NDK) | 只要求非空;实际由构建时实测比对 |

- `pin`用于Arch那边根本没有对应版本的东西:`ca-certificates`用的是curl的`cacert-<日期>.pem`,不是Arch的`mozilla-ca-certs`;`base-layout`与`ndk`更是本仓库自己的东西。
- `derived`用于"版本是别的输入的**输出**":`libc++`来自NDK sysroot。清单里那一格记的是在钉住的那颗NDK上**实测到的期望值**,`scripts/build-libs.sh`每次构建会从NDK头文件重新解析并比对。换一颗NDK,构建会直接失败,而不是静默产出一个版本不同的`libc++`。

## 几个刻意为之的约定

- `version`记的是**实际构建的版本**,不是Arch的`pkgver`。pacman在Arch上是`7.1.0.r9.g54d9411`这样的滚动快照,但我们钉的是`v7.1.0`这个tag,所以包里记的是`7.1.0`。
- `tar` / `tar_url` / `ref`都是**由版本号推导的模板**。钉一个版本就等于钉住了文件名与下载地址,不需要再手改第二处。
- `ndk`行的`kind`是`toolchain`,它**不发布为软件包**,而是记录"构建输入"。`env.sh`在每次构建前实测校验当前NDK是否就是这一行钉的版本;两个CI workflow也都从这里读取要安装的NDK。想换工具链,改这一行+`libc++`的期望值即可。

## tarball的`sha256`按版本存

`source=arch`的行里版本会随Arch自己往上走,所以校验值存成`{版本: 哈希}`而不是裸哈希:升版本时**不会**把旧版本的哈希误用到新tarball上,而是当场报"没有对应版本的sha256"。这条门禁在`--check`阶段生效,不用等到构建下载时才炸。

`source=pin`的行(如`ca-certificates`)版本与哈希是同时钉下的一对,写裸字符串即可。

走git的组件(`zlib` / `curl` / `pacman` / `vim` / `aria2`等)`tar`列为空,不需要sha256:它们的完整性由git的内容寻址加清单里钉住的`ref`保证,是另一套机制。

现有四个tarball钉值的来源(不是"本地算一个数就填上"):

| 包 | 证据 |
|---|---|
| `nano` | 与Arch `sha256sums[0]`逐字节相同 |
| `ncurses` | Arch从git snapshot tag构建,**无哈希可抄**;由invisible-mirror.net(上游作者站)与ftp.gnu.org各下载一次比对 |
| `wget` | Arch钉的是`.tar.lz`,与本仓库的`.tar.gz`**不是同一份产物**;由ftp.gnu.org与mirrors.kernel.org各下载一次比对 |
| `ca-certificates` | 原`build-ca-certificates.sh`已钉的值 |

镜像之间可能互为拷贝,所以"两个host一致"是**必要不充分**的证据。真要彻底确认得验上游detached signature(`.sig` / `.asc`),那需要引入GPG与密钥环,目前没做。
