#!/usr/bin/env bash

rootdir=$(cd $(dirname $0); pwd)
workdir="${rootdir}/src/corehost"
clidir="${workdir}/cli"
artifactsdir="${rootdir}/artifacts-patched"
patch="${rootdir}/0001-fix-additionalProbingPaths-resolver.patch"

rid=$1
segments=(${rid//-/ })
os=${segments[0]}
bit=${segments[1]}
arch=$bit
configuration=$2

if [[ $rid =~ "win" ]]; then
    platform="windows"
    hostfxr="hostfxr.dll"
elif [[ $rid =~ "linux" ]]; then
    platform="linux"
    hostfxr="libhostfxr.so"
elif [[ $rid =~ "osx" ]]; then
    platform="darwin"
    hostfxr="libhostfxr.dylib"
fi
version='0.0'
buildhash='00000000'
portable=
crossbuild=
stripsymbols=

if [[ $3 == 'True' ]]; then
    portable='-portable'
fi
if [[ $4 == 'True' ]]; then
    crossbuild='--cross'
fi
if [[ $5 == 'True' ]]; then
    stripsymbols='--stripsymbols'
fi

# 获取所有tag
tags=(`git tag`)

if [ ! -d $artifactsdir ]; then
    mkdir -p $artifactsdir
fi

# 增量编译
# 每次发布新版本之后在这里写
# tags=("v3.0.0" "v3.0.0-rc1-19456-20")
# tags=("v3.0.0")

for tag in ${tags[@]}
do
    # 只编译2.x以及3.x
    if [[ $tag == v2* || $tag == v3* ]]; then
        # 2.x版本只编译正式版
        if [[ $tag == v2* && $tag =~ [^v0-9\.] ]]; then
            continue
        fi
        cd ${rootdir}
        bindir="${artifactsdir}/${tag}/${rid}.${configuration}"
        if [ ! -d $bindir ]; then
            mkdir -p $bindir
        fi
        echo "${tag}编译中..."
        version=$tag
        git reset --hard HEAD
        git checkout $tag
        git am $patch
        git am --continue
        # 获取short commit id
        commithash=$(git rev-list --all --max-count=1 --abbrev-commit)
        buildhash=$commithash
        libPath1="${workdir}/cli/fxr/${hostfxr}"
        libPath2="${rootdir}/bin/${rid}.${configuration}/corehost/${hostfxr}"
        libPath3="${rootdir}/artifacts/bin/${rid}.${configuration}/corehost/${hostfxr}"
        libPath=''
        if [ -f $libPath1 ]; then
            rm $libPath1
        fi
        if [[ -f $libPath2 ]]; then
            rm $libPath2
        fi
        if [[ -f $libPath3 ]]; then
            rm $libPath3
        fi
        cd ${workdir}
        config="--configuration ${configuration} --arch ${arch} --hostver ${version} --apphostver ${version} --fxrver ${version} --policyver ${version} --commithash ${buildhash} ${portable} ${crossbuild} ${stripsymbols}"
        echo "buiding ${config}"
        ${workdir}/build.sh $config
        if [ -f $libPath1 ]; then
            libPath=$libPath1
        elif [[ -f $libPath2 ]]; then
            libPath=$libPath2
        elif [[ -f $libPath3 ]]; then
            libPath=$libPath3
        fi
        cp $libPath "${bindir}/${hostfxr}"
        git am --abort
        git reset --hard ${tag}
        if [[ -f ${workdir}/CMakeCache.txt ]]; then
            rm ${workdir}/CMakeCache.txt
        fi
        cd ${clidir}
        git clean -df
        cd ${workdir}
        echo "${tag}编译完成
"
    fi
done
