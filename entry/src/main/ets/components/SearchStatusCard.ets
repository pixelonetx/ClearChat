/**
 * SearchStatusCard.ets
 * 
 * 搜索状态卡片组件
 * 用于显示"正在搜索..."状态或搜索执行结果
 */

@Component
export struct SearchStatusCard {
  @Prop status: 'searching' | 'completed' | 'error'; // searching | completed | error
  @Prop query?: string;
  @Prop resultCount?: number;
  @Prop errorMessage?: string;
  @Prop executionTime?: number; // 毫秒

  build() {
    Column() {
      if (this.status === 'searching') {
        // 正在搜索状态
        Row() {
          LoadingProgress()
            .color(Color.Blue)
            .width(24)
            .height(24)
            .margin({ right: 12 })

          Column() {
            Text('🔍 正在搜索...')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor(Color.Black)

            if (this.query) {
              Text(this.query)
                .fontSize(12)
                .fontColor('#999999')
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
                .margin({ top: 4 })
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#F5F5F5')
        .borderRadius(8)
      } else if (this.status === 'completed') {
        // 搜索完成状态
        Column() {
          Row() {
            Text('✅ 搜索完成')
              .fontSize(14)
              .fontWeight(FontWeight.Medium)
              .fontColor('#4CAF50')

            if (this.executionTime !== undefined) {
              Text(`${this.executionTime}ms`)
                .fontSize(12)
                .fontColor('#999999')
                .layoutWeight(1)
                .textAlign(TextAlign.End)
            }
          }
          .width('100%')

          if (this.resultCount !== undefined && this.resultCount > 0) {
            Text(`找到 ${this.resultCount} 个搜索结果`)
              .fontSize(12)
              .fontColor('#666666')
              .margin({ top: 4 })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#E8F5E9')
        .borderRadius(8)
      } else if (this.status === 'error') {
        // 搜索失败状态
        Column() {
          Text('❌ 搜索失败')
            .fontSize(14)
            .fontWeight(FontWeight.Medium)
            .fontColor('#F44336')

          if (this.errorMessage) {
            Text(this.errorMessage)
              .fontSize(12)
              .fontColor('#D32F2F')
              .margin({ top: 4 })
              .maxLines(2)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
          }
        }
        .width('100%')
        .padding(12)
        .backgroundColor('#FFEBEE')
        .borderRadius(8)
      }
    }
    .width('100%')
  }
}
