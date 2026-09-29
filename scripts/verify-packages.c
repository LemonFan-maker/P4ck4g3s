#include <alpm.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>
#include <sys/stat.h>

#define BAD_PREFIX "system/0vl0ad3r/"

static int failures = 0;

static void fail(const char *file, const char *fmt, const char *detail) {
	printf("[FAIL] %s %s: %s\n", file, fmt, detail);
	failures++;
}

int main(int argc, char **argv) {
	alpm_errno_t err = 0;

	mkdir("/tmp/.pkg-verify", 0755);
	mkdir("/tmp/.pkg-verify/var", 0755);
	mkdir("/tmp/.pkg-verify/var/lib", 0755);
	mkdir("/tmp/.pkg-verify/var/lib/pacman", 0755);
	mkdir("/tmp/.pkg-verify/var/lib/pacman/local", 0755);
	mkdir("/tmp/.pkg-verify/cache", 0755);

	alpm_handle_t *h = alpm_initialize("/tmp/.pkg-verify", "/tmp/.pkg-verify/cache", &err);
	if (!h) {
		fprintf(stderr, "alpm_initialize failed: %s\n", alpm_strerror(err));
		return 2;
	}

	size_t cap = (size_t)(argc - 1), loaded = 0;
	alpm_pkg_t **pkgs = calloc(cap ? cap : 1, sizeof(*pkgs));
	if (!pkgs) { return 2; }

	for (int i = 1; i < argc; i++) {
		const char *file = argv[i];
		alpm_pkg_t *pkg = NULL;
		int failures_before = failures;
		err = 0;

		if (alpm_pkg_load(h, file, 1, 0, &pkg) == -1) {
			fail(file, "alpm_pkg_load", alpm_strerror(err));
			continue;
		}
		pkgs[loaded++] = pkg;

		const char *name = alpm_pkg_get_name(pkg);
		const char *ver = alpm_pkg_get_version(pkg);
		const char *arch = alpm_pkg_get_arch(pkg);

		if (!name) { fail(file, "pkgname", "为空(归档元数据不可解析)"); }
		if (!ver) { fail(file, "pkgver", "为空(文件名不可解析)"); }
		if (!arch) { fail(file, "pkgarch", "为空(文件名不可解析)"); }

		alpm_filelist_t *files = alpm_pkg_get_files(pkg);
		size_t n = files ? files->count : 0;
		size_t ndeps = 0;
		alpm_list_t *d;
		for (d = alpm_pkg_get_depends(pkg); d; d = d->next) { ndeps++; }
		if (n == 0 && ndeps == 0) { fail(file, "files", "空包且无依赖(应为metapackage或构建事故)"); }

		int badprefix = 0;
		for (size_t j = 0; files && j < files->count; j++) {
			const char *fn = files->files[j].name;
			if (fn && strncmp(fn, BAD_PREFIX, strlen(BAD_PREFIX)) == 0) {
				fail(file, "路径含system/0vl0ad3r前缀", fn);
				badprefix = 1;
				break;
			}
		}

		if (failures == failures_before && !badprefix) {
			printf("[OK] %s %s %s arch=%s files=%zu\n",
			       file, name ? name : "?", ver ? ver : "?", arch ? arch : "?", n);
		}
	}

	for (size_t a = 0; a < loaded; a++) {
		alpm_filelist_t *fa = alpm_pkg_get_files(pkgs[a]);
		for (size_t b = a + 1; b < loaded; b++) {
			alpm_filelist_t *fb = alpm_pkg_get_files(pkgs[b]);
			for (size_t x = 0; fa && x < fa->count; x++) {
				if (S_ISDIR(fa->files[x].mode)) continue;
				for (size_t y = 0; fb && y < fb->count; y++) {
					if (S_ISDIR(fb->files[y].mode)) continue;
					if (fa->files[x].name && fb->files[y].name &&
					    strcmp(fa->files[x].name, fb->files[y].name) == 0) {
						char detail[512];
						snprintf(detail, sizeof(detail), "%s与%s争夺同一文件",
						         alpm_pkg_get_name(pkgs[a]), alpm_pkg_get_name(pkgs[b]));
						fail(fa->files[x].name, "跨包文件冲突", detail);
					}
				}
			}
		}
	}

	for (size_t i = 0; i < loaded; i++) { alpm_pkg_free(pkgs[i]); }
	free(pkgs);

	alpm_release(h);
	if (failures) {
		printf("\n校验失败:%d项问题\n", failures);
		return 1;
	}
	printf("\n全部通过(%d个包)\n", argc - 1);
	return 0;
}
