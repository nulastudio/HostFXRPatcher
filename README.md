# HostFXRPatcher

## Environment Requirements
1. Hosting System (Windows/Linux(WSL works too)/MacOS)
2. PowerShell 7
3. Visual Studio 2017 (Windows Only)
4. Visual Studio 2019 (Windows Only)
5. Basic build environment by [this guide](https://github.com/dotnet/runtime/blob/main/docs/workflow/README.md)

## Clone Or Update The `core-setup`/`runtime` Repo

`core-setup` repo is for `.NET Core 2.x` and `.NET Core 3.x`, and `runtime` repo is for `.NET 5` and `.NET 6`.
```shell
git clone https://github.com/dotnet/core-setup.git
git clone https://github.com/dotnet/runtime.git
```

## Fork And Clone This `HostFXRPatcher` Repo And Switch To `Patcher` Branch To Get The Build Scripts

**FORK FIRST PLEASE!**

```shell
git clone https://github.com/<YOU>/HostFXRPatcher.git
git checkout Patcher
```

## Copy The Build Scripts Into `core-setup`/`runtime` Repo

```shell
cp <HostFXRPatcher repo>/HostFXRPatcher/ <core-setup/runtime repo>
```

## Fetch The Latest Release Versions

```shell
cd <core-setup/runtime repo>/HostFXRPatcher/
pwsh ./updateVersionReleases.ps1
```

## Building
There are two ways to build the `hostfxr` depending on which versions you need to build.

### Usage

```shell
pwsh ./buildPatch.ps1 -rid <RID> -configuration <Configuration=Debug|Release> [-portable] [-cross] [-stripsymbols]
```

### Building All The Versions
Just delete the `VersionBuilt.json` that is under the `HostFXRPatcher` folder.

```shell
cd <core-setup/runtime repo>/HostFXRPatcher/
rm VersionBuilt.json

pwsh ./buildPatch.ps1 -rid win-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid win-x86 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid linux-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid osx-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid osx-arm64 -configuration Release -portable -stripsymbols -cross
ROOTFS_DIR=/home/cross/arm pwsh ./buildPatch.ps1 -rid linux-arm -configuration Release -portable -stripsymbols -cross
ROOTFS_DIR=/home/cross/arm64 pwsh ./buildPatch.ps1 -rid linux-arm64 -configuration Release -portable -stripsymbols -cross
```

### Building The Missing Versions
Modify the `buildPatch.ps1` script and uncomment line 231-234 and add any verisons that you want to build, then run the build script.

```powershell
# 自定义版本编译
$tags = @()
[void]$tags.Add("v2.2.0")
[void]$tags.Add("v3.0.0")
[void]$tags.Add("v5.0.0")
```

```shell
cd <core-setup/runtime repo>/HostFXRPatcher/

pwsh ./buildPatch.ps1 -rid win-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid win-x86 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid linux-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid osx-x64 -configuration Release -portable -stripsymbols
pwsh ./buildPatch.ps1 -rid osx-arm64 -configuration Release -portable -stripsymbols -cross
ROOTFS_DIR=/home/cross/arm pwsh ./buildPatch.ps1 -rid linux-arm -configuration Release -portable -stripsymbols -cross
ROOTFS_DIR=/home/cross/arm64 pwsh ./buildPatch.ps1 -rid linux-arm64 -configuration Release -portable -stripsymbols -cross
```

## Get The Artifacts
When the build is done, all the artifacts are copied to the `artifacts-patched` folder.

## Make You Own `HostFXRPatcher` Repo
**NetCoreBeauty DOES NOT ACCEPT ANY ARTIFACTS PR**

Copy all the artifacts into the `HostFXRPatcher` repo(`artifacts` folder), but switch back to `master` branch first please, and then run the `autoUpdateArtifacts.ps1`. Finally, push the update.
```shell
cp <HostFXRPatcher repo>/
pwsh ./autoUpdateArtifacts.ps1
git commit -m "Update Versions"
git push
```

## Use You Own `HostFXRPatcher` Patch In NetCoreBeauty
Just [setting the mirror](https://github.com/nulastudio/NetBeauty2/tree/v1#mirror) and republish your project.
