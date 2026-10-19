## 算子代码检查整改项汇总

一, 代码规范与性能优化

1. 检查项: 建议不要使用数据类型区分 tilingKey, 会导致编译出来的算子二进制文件膨胀
   修改方案: 建议尽可能减少 tilingKey 设置, 可在 kernel 使用 T_DYPE 宏区分数据类型(非强制)

2. 检查项: const 建议改为 constexpr, 可以在编译时确定, 避免运行时开销
   修改方案: 将 const 修改为 constexpr

3. 检查项: 建议在使用 context 指针前判断其是否为 nullptr
   修改方案: API 返回指针, 应判断返回值是否为 nullptr

4. 检查项: BLOCK_SIZE 不建议硬编码为 32
   修改方案: 可使用宏代码数字

5. 检查项: coreNum <= 0, ubSize <= 0 均可能是非法值
   修改方案: 非负数值获取后应该做非负数判断

6. 检查项: 变量相除前需要除零检测
   修改方案: 使用 if 语句或者 OP_CHECK_IF 宏进行除零检测

7. 检查项: 抛出异常前请打印 ERROR 日志
   修改方案: 对于异常场景需要抛出 ERROR 日志并说明原因

8. 检查项: 代码缩进风格保持一致
   修改方案: 使用一致代码缩进风格

9. 检查项: host 数据类型转换, 建议使用 C++ 风格 static_cast<>()
   修改方案: 例如: `tiling->bigTailDataNum = static_cast<uint64_t>(bigTailDataNum);`

10. 检查项: 头文件需要加入条件编译, 防止编译冲突
    修改方案: #ifndef SQRT_TILING_DATA_H / #define SQRT_TILING_DATA_H / ...... / #endif

11. 检查项: 变量名称含义清晰, 防止歧义
    修改方案: 根据变量含义和单位采用统一风格命名

12. 检查项: kernel 侧使用 AscendC::Cast 时需要注意 RoundMode 的选择, 尽可能减小数据误差
    修改方案: 根据 cast API 文档选择最佳转换模式

13. 超大函数检查项: 建议将函数内容封装至 50 行以内(非强制)

14. 检查项: 将多余空行删除
