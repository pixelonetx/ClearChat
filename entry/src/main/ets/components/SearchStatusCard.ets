/**
 * SearchStatusCard.ets
 * 
 * 搜索状态卡片组件 - 优化版
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
        // 正在搜索状态 - 优化版
        Row({ space: 12 }) {
          LoadingProgress()
            .color($r('sys.color.ohos_id_color_emphasize'))
            .width(28)
            .height(28)

          Column({ space: 4 }) {
            Text('🔍 正在联网搜索')
              .fontSize(15)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('sys.color.ohos_id_color_text_primary'))

            if (this.query) {
              Text(`"${this.query}"`)
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                .maxLines(1)
                .textOverflow({ overflow: TextOverflow.Ellipsis })
            } else {
              Text('正在获取最新信息...')
                .fontSize(12)
                .fontColor($r('sys.color.ohos_id_color_text_secondary'))
            }
          }
          .layoutWeight(1)
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#F0F7FF')
        .borderRadius(12)
        .border({
          width: 1,
          color: '#D0E7FF'
        })
        .shadow({
          radius: 6,
          color: 'rgba(0, 100, 255, 0.1)',
          offsetX: 0,
          offsetY: 2
        })
        .animation({
          duration: 800,
          iterations: -1,
          curve: Curve.EaseInOut
        })
        
      } else if (this.status === 'completed') {
        // 搜索完成状态 - 优化版
        Column({ space: 10 }) {
          Row({ space: 10 }) {
            Image($r('sys.symbol.checkmark_circle_fill'))
              .width(24)
              .height(24)
              .fillColor(Color.Green)

            Column({ space: 4 }) {
              Text('✅ 搜索完成')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor($r('sys.color.ohos_id_color_text_primary'))
              
              if (this.resultCount !== undefined && this.resultCount > 0) {
                Row({ space: 6 }) {
                  Text(`找到 ${this.resultCount} 个搜索结果`)
                    .fontSize(12)
                    .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  
                  if (this.executionTime !== undefined) {
                    Text('•')
                      .fontSize(12)
                      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                    
                    Text(`${this.executionTime}ms`)
                      .fontSize(12)
                      .fontColor($r('sys.color.ohos_id_color_text_secondary'))
                  }
                }
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#E8F5E9')
        .borderRadius(12)
        .border({
          width: 1,
          color: '#C8E6C9'
        })
        .shadow({
          radius: 6,
          color: 'rgba(76, 175, 80, 0.1)',
          offsetX: 0,
          offsetY: 2
        })
        
      } else if (this.status === 'error') {
        // 搜索失败状态 - 优化版
        Column({ space: 8 }) {
          Row({ space: 10 }) {
            Image($r('sys.symbol.exclamationmark_circle_fill'))
              .width(24)
              .height(24)
              .fillColor('#F44336')

            Column({ space: 4 }) {
              Text('❌ 搜索失败')
                .fontSize(15)
                .fontWeight(FontWeight.Medium)
                .fontColor('#D32F2F')

              if (this.errorMessage) {
                Text(this.errorMessage)
                  .fontSize(12)
                  .fontColor('#D32F2F')
                  .maxLines(2)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
              } else {
                Text('请稍后重试')
                  .fontSize(12)
                  .fontColor('#D32F2F')
              }
            }
            .layoutWeight(1)
            .alignItems(HorizontalAlign.Start)
          }
          .width('100%')
        }
        .width('100%')
        .padding(16)
        .backgroundColor('#FFEBEE')
        .borderRadius(12)
        .border({
          width: 1,
          color: '#FFCDD2'
        })
        .shadow({
          radius: 6,
          color: 'rgba(244, 67, 54, 0.1)',
          offsetX: 0,
          offsetY: 2
        })
      }
    }
    .width('100%')
    .transition(TransitionEffect.OPACITY.animation({ duration: 300 }))
  }
}
