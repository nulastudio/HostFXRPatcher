# HostFXRPatcher

## 编译流程
1.  拉取最新HostFXRPatcher
2.  拉取最新core-setup
3.  切换至HostFXRPatcher/patcher分支
4.  运行updateVersionReleases.ps1更新VersionReleased.json
5.  对比VersionReleased.json与VersionBuilt.json
6.  找出缺失的Version并编译
7.  更新VersionReleased.json与VersionBuilt.json
8.  推送HostFXRPatcher/patcher分支
9.  切换至HostFXRPatcher/master分支
10. 运行checkMissingArtifacts.ps1找出缺失的Arch编译
11. build缺失的特定版本的特定Arch
12. 运行autoUpdateArtifacts.ps1自动更新ArtifactsVersion
13. 推送HostFXRPatcher/master分支

## 特殊
1.  更新runtime.compatibility.json（从URL拉取最新数据并更新，可自动），位于HostFXRPatcher/master/artifacts/runtime.compatibility.json
2.  更新runtime.supported.json（基本不会更新，除非加入新的Arch支持），位于HostFXRPatcher/master/artifacts/runtime.supported.json
3.  ArtifactsVersion现已自动管理，不再需要配人为操作
4.  更新VersionMapping.json（用于解决core-setup的tag与version不统一的情况），位于HostFXRPatcher/patcher/Patcher/VersionMapping.json
