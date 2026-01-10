#!/usr/bin/env bash
# verify-fixes.sh - 验证所有修复是否正确应用

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "$0")" && pwd)"
cd "$ROOT_DIR"

echo "=========================================="
echo "验证审计修复"
echo "=========================================="
echo ""

ERRORS=0
WARNINGS=0

# 检查 1: batch-check/service.yaml 已删除
echo "1️⃣  检查 batch-check/service.yaml..."
if [ -f "scenarios/batch-check/service.yaml" ]; then
  echo "  ❌ FAILED: batch-check/service.yaml 仍然存在"
  ((ERRORS++))
else
  echo "  ✅ PASS: batch-check/service.yaml 已删除"
fi
echo ""

# 检查 2: poor-registry NodePort
echo "2️⃣  检查 poor-registry NodePort..."
if grep -q "nodePort: 30004" scenarios/poor-registry/deployment.yaml; then
  echo "  ✅ PASS: poor-registry nodePort 已设置为 30004"
else
  echo "  ❌ FAILED: poor-registry nodePort 未设置为 30004"
  ((ERRORS++))
fi

if grep -q "type: NodePort" scenarios/poor-registry/deployment.yaml; then
  echo "  ✅ PASS: poor-registry Service type 为 NodePort"
else
  echo "  ❌ FAILED: poor-registry Service type 未设置为 NodePort"
  ((ERRORS++))
fi
echo ""

# 检查 3: system-monitor NodePort
echo "3️⃣  检查 system-monitor NodePort..."
if grep -q "nodePort: 30008" scenarios/system-monitor/deployment.yaml; then
  echo "  ✅ PASS: system-monitor nodePort 已设置为 30008"
else
  echo "  ❌ FAILED: system-monitor nodePort 未设置为 30008"
  ((ERRORS++))
fi

if grep -q "type: NodePort" scenarios/system-monitor/deployment.yaml; then
  echo "  ✅ PASS: system-monitor Service type 为 NodePort"
else
  echo "  ❌ FAILED: system-monitor Service type 未设置为 NodePort"
  ((ERRORS++))
fi
echo ""

# 检查 4: deploy-kind.sh 中的 kind-config 已更新
echo "4️⃣  检查 deploy-kind.sh kind-config 更新..."
if grep -q "containerPort: 30004" scripts/deploy-kind.sh; then
  echo "  ✅ PASS: kind-config 包含 containerPort 30004"
else
  echo "  ⚠️  WARNING: kind-config 缺少 containerPort 30004"
  ((WARNINGS++))
fi

if grep -q "containerPort: 30008" scripts/deploy-kind.sh; then
  echo "  ✅ PASS: kind-config 包含 containerPort 30008"
else
  echo "  ⚠️  WARNING: kind-config 缺少 containerPort 30008"
  ((WARNINGS++))
fi

if grep -q "hostPort: 1238" scripts/deploy-kind.sh; then
  echo "  ✅ PASS: kind-config 包含 hostPort 1238 映射"
else
  echo "  ⚠️  WARNING: kind-config 缺少 hostPort 1238 映射"
  ((WARNINGS++))
fi

if grep -q "hostPort: 1237" scripts/deploy-kind.sh; then
  echo "  ✅ PASS: kind-config 包含 hostPort 1237 映射"
else
  echo "  ⚠️  WARNING: kind-config 缺少 hostPort 1237 映射"
  ((WARNINGS++))
fi
echo ""

# 检查 5: 其他服务的 nodePort 没有冲突
echo "5️⃣  检查 nodePort 冲突..."
nodeports=$(grep -r "nodePort:" scenarios/ --include="*.yaml" 2>/dev/null | grep -o "nodePort: [0-9]*" | sort | uniq -d || true)
if [ -z "$nodeports" ]; then
  echo "  ✅ PASS: 没有 nodePort 重复"
else
  echo "  ❌ FAILED: 发现重复的 nodePort:"
  echo "$nodeports"
  ((ERRORS++))
fi
echo ""

# 检查 6: 所有暴露的 Service (NodePort) 都有 nodePort
echo "6️⃣  检查所有 NodePort Service 都有 nodePort 字段..."
services=$(grep -r "type: NodePort" scenarios/ --include="*.yaml" -B 10 | grep "metadata:" -A 10 | grep "name:" | sed 's/.*name: //' || true)
missing_nodeport=0

# 查找所有定义 type: NodePort 的 yaml 文件
for yaml_file in $(grep -r "type: NodePort" scenarios/ --include="*.yaml" -l); do
  if ! grep -q "nodePort:" "$yaml_file"; then
    echo "  ⚠️  WARNING: $yaml_file 定义了 type: NodePort 但缺少 nodePort 字段"
    ((missing_nodeport++))
  fi
done

if [ "$missing_nodeport" -eq 0 ]; then
  echo "  ✅ PASS: 所有 NodePort Service 都定义了 nodePort 字段"
else
  echo "  ⚠️  $missing_nodeport 个 NodePort Service 缺少 nodePort 字段"
fi
echo ""

# 检查 7: 其他 Service 类型的检查
echo "7️⃣  检查 Service 配置完整性..."
cri_errors=$(grep -r "/var/run/cri-dockerd.sock" scenarios/ --include="*.yaml" 2>/dev/null || true)
if [ -z "$cri_errors" ]; then
  echo "  ℹ️  INFO: 未发现硬编码的 /var/run/cri-dockerd.sock（将由脚本修复）"
else
  echo "  ℹ️  INFO: 发现以下文件需要 CRI socket 修复（由脚本处理）："
  echo "$cri_errors" | cut -d: -f1 | sort -u | sed 's/^/     - /'
fi
echo ""

echo "=========================================="
echo "验证结果"
echo "=========================================="
echo "❌ 错误数: $ERRORS"
echo "⚠️  警告数: $WARNINGS"
echo ""

if [ $ERRORS -eq 0 ]; then
  echo "✅ 所有关键检查通过！准备部署。"
  echo ""
  echo "下一步: bash scripts/deploy-kind.sh"
  exit 0
else
  echo "❌ 存在错误，请先修复后再部署。"
  exit 1
fi
