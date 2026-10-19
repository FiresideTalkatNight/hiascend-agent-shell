三, 目录与文件结构

1. 算子 op_host/下的 config 目录和文件不需要
   -> 删除 op_host/下的 config 目录及文件

2. def.cpp 文件中算子原型部分不需要支持不要求支持的数据类型和数据格式
   -> 和 AscendC 设计文档支持的数据类型和格式保持一致

3. op_host/infershape.cpp 缺失
   -> 文件需要保留

4. 冗余的数据类型强转
   -> 不支持同数据类型强转

5. ${op_name}_tiling.cpp 中 GET_TPL_TILING_KEY() 需要去除魔鬼数字
   -> 设置需要使用 kernel 的宏

6. UT 测试只需要测试 op_host, op_kernel, op_api
   -> 需要包含 op_host, op_kernel, op_api 三部分 UT 测试

7. 算子目录外层 README.md 中缺少贡献说明部分
   -> 需补充贡献说明

8. ${op_name}/op_graph 入图文件不需要
   -> 删除该目录 ${op_name}/op_graph

9. op_host/CmakeLists.txt 中 ACLNNTYPE 的值错误
   -> ACLNNTYPE 应设置为 aclnn_exclude

10. aicoreConfig.DynamicCompileStaticFlag(true) 等冗余内容不需要
    -> 包括 .DynamicFormatFlag(false) 等冗余配置均不需要

11. op_host 实现文件需要拆分为 ${op_name}_def.cpp 和 ${op_name}_tiling.cpp
    -> kernel 需要实现算子声明实现分离, tilingdata 使用标准 C++ 形式, tilingKey 使用 tilingKey 模板形式注册

四, 参考与示例

- 参考贡献包 Abs 算子:
  https://gitcode.com/cann/ops-math/blob/master/math/abs

- 参考 Sqrt 算子:
  https://gitcode.com/cann/ops-math/tree/master/experimental/math/sqrt

- 可参考 add_example:
  https://gitcode.com/cann/ops-math/tree/master/examples/add_example

- 建议参考上述示例算子进行整改, 保持代码风格, 目录结构和接口设计与社区一致
