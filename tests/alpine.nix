# SPDX-License-Identifier: GPL-3.0-or-later
{ pkgs }:
{
  rootfs = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/releases/x86_64/alpine-minirootfs-3.22.2-x86_64.tar.gz";
    hash = "sha256-QSRU7ZgCWtnNkQ0T89RIsYToFQK6qDGA6J+Y0PE2dL4=";
  };
  openrc = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/openrc-0.62.6-r0.apk";
    hash = "sha256-ivdvGADJGyQXRWnr83LEOOtjMoUT3XILJhvZk5cX7RE=";
  };
  openrc-user = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/openrc-user-0.62.6-r0.apk";
    hash = "sha256-pj7x3hJUTN2o4ZjL/1jJizsxhZnXyrujwLQ7kvUnzJU=";
  };
  libcap = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/libcap2-2.78-r0.apk";
    hash = "sha256-mFB1m7sW8f9tGkncmZR+8UAeHBDlyiT4OA5puhnwd8k=";
  };
  ifupdown = pkgs.fetchurl {
    url = "https://dl-cdn.alpinelinux.org/alpine/v3.22/main/x86_64/busybox-ifupdown-1.37.0-r20.apk";
    hash = "sha256-Yf9K/wap3keXfFEkSISVva3w8HBmBuGZKQq+HY4MRH0=";
  };
}
