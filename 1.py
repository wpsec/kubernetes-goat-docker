from pathlib import Path

# 需要汇总的 YAML 文件（按 kubectl apply 的顺序）
yaml_files = [
    "scenarios/batch-check/job.yaml",
    "scenarios/build-code/deployment.yaml",
    "scenarios/cache-store/deployment.yaml",
    "scenarios/health-check/deployment.yaml",
    "scenarios/hunger-check/deployment.yaml",
    "scenarios/internal-proxy/deployment.yaml",
    "scenarios/kubernetes-goat-home/deployment.yaml",
    "scenarios/poor-registry/deployment.yaml",
    "scenarios/system-monitor/deployment.yaml",
    "scenarios/hidden-in-layers/deployment.yaml",
]

output_md = Path("all-yamls.md")

with output_md.open("w", encoding="utf-8") as out:
    out.write("# Kubernetes YAML 汇总\n\n")

    for yaml_path in yaml_files:
        path = Path(yaml_path)
        out.write(f"## {yaml_path}\n\n")

        if not path.exists():
            out.write("```text\n")
            out.write("⚠️ 文件不存在\n")
            out.write("```\n\n")
            continue

        content = path.read_text(encoding="utf-8")
        out.write("```yaml\n")
        out.write(content.rstrip())
        out.write("\n```\n\n")

print(f"已生成：{output_md.resolve()}")

