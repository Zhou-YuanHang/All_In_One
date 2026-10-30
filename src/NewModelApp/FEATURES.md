# NewModelApp 功能测试记录

| # | 功能 | 状态 | 备注 |
|---|------|------|------|
| 1 | 模型名称输入与校验 | ✅ 已测 | 验证空名称、非法标识符；已存在时弹对话框选覆盖/加后缀 |
| 2 | 创建模型（离散/连续求解器） | ✅ 已测 | 离散勾选后启用固定步长配置 |
| 3 | TLC 文件选择 | ✅ 已测 | 默认 ert.tlc，支持浏览选择 |
| 4 | 仅生成代码 | ✅ 已测 | 勾选后设置 GenCodeOnly=on |
| 5 | 数据字典关联 | ✅ 已测 | 勾选后选择 .sldd 文件，通过 `set_param` 关联；文件不存在时提示先创建 |
| 6 | 从 Excel 导入端口 | ✅ 已测 | 读取 端口名称 / 数据类型 / StorageClass / Identifier（B ~ E列）；支持 Inputs/Input/Outputs/Output 工作表 |
| 6a | Code Mapping（StorageClass/Identifier） | ✅ 已测 | 勾选后保存模型 → `coder.mapping.utils.create` → `setInport/setOutport` 设置；每个端口独立 try-catch，单个端口配置失败不影响其他端口，结束后弹窗列出失败的端口名 |
| 7 | 已存在模型处理 | ✅ 已测 | 覆盖（删除重建）/ 加数字后缀（自动递进）/ 取消 |
| 8 | 创建后打开模型 | ✅ 已测 | 勾选则保存后保持打开，不勾选则关闭 |
| 9 | Excel 端口模板生成 | ✅ 已测 | `createExcelTemplate.m` 生成 4 输入 + 3 输出端口模板 |
