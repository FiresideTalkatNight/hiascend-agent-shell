# 代码风格

你进行所有代码修改时, 应该符合以下规则:

## 开源贡献算子代码常见问题

1. BLOCK SIZE硬编码

- 错误示例

```cpp
constexpr uint32_t BLOCK_SIZE = 32;
```

- 修改建议

```cpp
uint32_t BLOCK_SIZE = Ops::Base::GetUbBlockSize(context)
```

- 原因说明
  硬编码会导致代码的兼容性差; 通过函数获取, 增加兼容性.

2. 单行选择语句未加大括号

- 错误示例

```cpp
if (tileDataNum == 0U) tileDataNum = 1U;
```

- 修改建议

```cpp
if (tileDataNum == 0U) {
    tileDataNum = 1U;
}
```

- 原因说明
  单行选择语句需要加大括号; 使代码逻辑直观, 易读.

3. int32数据类型Cast成half时未结合SetDeqScale接口使用

- 错误示例

```cpp
AscendC::Cast(zLocal, xLocal, AscendC::RoundMode::CAST_NONE, this->processDataNum);
```

- 修改建议

```cpp
if (std::is_same<T1, half>::value) {
    half scale = 1.0;
        AscendC::SetDeqScale(scale);
        AscendC::Cast(zLocal, xLocal, AscendC::RoundMode::CAST_NONE, this->processDataNum);
}
```

- 原因说明
  int32转half时Cast接口需要与SetDeqScale(half scale)接口配合使用;
  详见: https://www.hiascend.com/document/detail/zh/canncommercial/83RC1/API/ascendcopapi/atlasascendc_api_07_0073.html

4. 使用DataCopy搬运非对齐数据

- 错误示例

```cpp
AscendC::DataCopy(yGm[progress * this->tileDataNum], yLocal, this->processDataNum);
```

- 修改建议

```cpp
AscendC::DataCopyExtParams copyParams{1, this->processDataNum * sizeof(T), 0, 0, 0};
AscendC::DataCopyPad(yGm[progress * this->tileDataNum], yLocal, copyParams);
```

- 原因说明
  DataCopy在搬运数据时count * sizeof(T)需要32字节对齐, 若不对齐, 搬运量将对32字节做向下取整. 当尾块数据不是32B的倍数时, 建议使用DataCopyPad, 避免数据搬运不完整.

5. 单语句执行多个变量检查

- 错误示例

```cpp
OP_CHECK_IF(context == nullptr || context->GetInputShape(0) == nullptr,
           OP_LOGE(context, "context is nullptr"),
           return ge::GRAPH_FAILED);
```

- 修改建议

```cpp
OP_CHECK_IF(context == nullptr, OP_LOGE(context, "context is nullptr"), return ge::GRAPH_FAILED);
auto shapeInputPrt = context->GetInputShape(0);
OP_CHECK_NULL_WITH_CONTEXT(context, shapeInputPtr);
```

- 原因说明
  一个检查语句只做一个明确的检查

6. 避免使用for循环赋值

- 错误示例

```cpp
auto xShapeSize = xShape->GetDimNum();
yShape->SetDimNum(xShapeSize);
for (size_t i = 0; i < xShapeSize; i++) {
    int64_t dim = xShape->GetDim(i);
    yShape->SetDim(i, dim);
}
```

- 修改建议

```cpp
auto xShapeSize = xShape->GetDimNum();
yShape->SetDimNum(xShapeSize);
*yShape = *xShape
```

- 原因说明
  避免使用for循环赋值, 提升性能和代码可读易理解性.

7. 命名无法表达真实语义

- 错误示例

```cpp
uint32_t coreNum = AscendC::GetBlockIdx();
```

- 修改建议

```cpp
uint32_t blockIdx = AscendC::GetBlockIdx();
```

- 原因说明
  使用语义相似的单词命名变量

8. 参数参数过多

- 错误示例

```cpp
__aicore__ inline void Init(GM_ADDR x, GM_ADDR y, uint32_t smallCoreDataNum,
                            uint32_t bigCoreDataNum, uint32_t finalBigTileNum,
                            uint32_t finalSmallTileNum, uint32_t tileDataNum,
                            uint32_t smallTailDataNum, uint32_t bigTailDataNum,
                            uint32_t tailBlockNum,float decimals);
```

- 修改建议

```cpp
__aicore__ inline void Init(GM_ADDR x, GM_ADDR y, RoundTilingData *tilingData);
```

- 原因说明
  函数参数过多, 建议直接传tilingData后在函数中进行解析或直接使用.

9. 冗余计算

- 错误示例

```cpp
uint32_t inputLength = inputNum * typeLength;
uint32_t inputBytes = inputLength / inputNum;
```

- 修改建议

```cpp
uint32_t inputBytes = typeLength;
```

- 原因说明
  重复计算了inputBytes, 直接使用typeLength即可.

10. 返回失败前未打印日志表明失败原因

- 错误示例

```cpp
if (socVersion != platform_ascendc::SocVersion::ASCEND910B && socVersion != platform_ascendc::SocVersion::ASCEND310B && context->GetInputDesc(0)->GetDataType() == ge::DT_BF16)
{
    return ge::GRAPH_FAILED;
}
```

- 修改建议

```cpp
if (socVersion != platform_ascendc::SocVersion::ASCEND910B && socVersion != platform_ascendc::SocVersion::ASCEND310B && context->GetInputDesc(0)->GetDataType() == ge::DT_BF16)
{
    OP_LOGE(context, "do not support bf16 on this platform.")
    return ge::GRAPH_FAILED;
}
```

- 原因说明
  返回失败前打印日志表示具体失败原因, 增加可维护性.

11. 指针在使用前未判空

- 错误示例

```cpp
uint32_t inputNum = context->GetInputShape(0)->GetStorageShape().GetShapeSize();
```

- 修改建议

```cpp
auto inputShapePtr = context->GetInputShape(0);
OP_CHECK_NULL_WITH_CONTEXT(context, inputShapePtr);
uint32_t inputNum = inputShapePtr->GetStorageShape().GetShapeSize();
```

- 原因说明
  指针在使用前需要判空, 避免空指针导致未定义行为和程序崩溃.

12. 基础数据类型在定义时未初始化

- 错误示例

```cpp
private:
    uint64_t coreDataNum;
    uint64_t tileNum;
    uint64_t ubPartDataNum;
    uint64_t tailDataNum;
    uint64_t processDataNum;
```

- 修改建议

```cpp
private:
    uint64_t coreDataNum = 0;
    uint64_t tileNum = 0;
    uint64_t ubPartDataNum = 0;
    uint64_t tailDataNum = 0;
    uint64_t processDataNum = 0;
```

- 原因说明
  基础数据类型在定义时未初始化会导致读取未定义的值, 引发不可预测的行为.

13. 指针在解引用前未判空

- 错误示例

```cpp
const float* scale = attrs->GetAttrPointer<float>(1);
tiling->scale = *scale;
```

- 修改建议

```cpp
const float *scale = attrs->GetAttrPointer<float>(1);
OP_CHECK_NULL_WITH_CONTEXT(context, scale);
tiling->scale = *scale;
```

- 原因说明
  指针在解引用前需要判空, 避免空指针导致未定义行为和程序崩溃.
  每个变量单独一行声明或赋值. 不要一行赋值多个变量.
