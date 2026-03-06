/**
 * BaseComponents.ets
 * 基础 UI 组件库
 *
 * 职责：提供可复用的基础 UI 组件
 */

import { AppConfig, ColorResources, AnimationCurves } from '../../common/Constants';

/**
 * 加载指示器组件
 */
@Component
export struct LoadingIndicator {
  @Prop indicatorSize: number = 24; // 重命名：size -> indicatorSize
  @Prop color: ResourceColor = ColorResources.ACCENT;

  build() {
    LoadingProgress()
      .width(this.indicatorSize)
      .height(this.indicatorSize)
      .color(this.color)
  }
}

/**
 * 空状态组件
 */
@Component
export struct EmptyState {
  @Prop icon: Resource = $r('app.media.trash');
  @Prop title: string = '暂无数据';
  @Prop subtitle: string = '';

  build() {
    Column({ space: 12 }) {
      Image(this.icon)
        .width(64)
        .height(64)
        .fillColor(ColorResources.TEXT_SECONDARY)
        .opacity(0.5)

      Text(this.title)
        .fontSize(16)
        .fontColor(ColorResources.TEXT_SECONDARY)

      if (this.subtitle) {
        Text(this.subtitle)
          .fontSize(14)
          .fontColor(ColorResources.TEXT_SECONDARY)
          .opacity(0.7)
      }
    }
    .width('100%')
    .padding(32)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 分割线组件
 */
@Component
export struct DividerLine {
  @Prop thickness: number = 0.5;
  @Prop verticalMargin: number = 0; // 重命名：margin -> verticalMargin
  @Prop color: ResourceColor = ColorResources.BORDER_PRIMARY;

  build() {
    Divider()
      .height(this.thickness)
      .color(this.color)
      .margin({ top: this.verticalMargin, bottom: this.verticalMargin })
  }
}

/**
 * 图标按钮组件
 */
@Component
export struct IconButton {
  @Prop icon: Resource;
  @Prop iconSize: number = 24;      // 重命名：size -> iconSize
  @Prop iconPadding: number = 8;    // 重命名：padding -> iconPadding
  @Prop iconColor: ResourceColor = ColorResources.TEXT_PRIMARY;
  @Prop bgColor: ResourceColor = Color.Transparent;
  @Prop disabled: boolean = false;
  onTap?: () => void;

  build() {
    Button({ type: ButtonType.Circle }) {
      Image(this.icon)
        .width(this.iconSize)
        .height(this.iconSize)
        .fillColor(this.disabled ? ColorResources.TEXT_SECONDARY : this.iconColor)
    }
    .width(this.iconSize + this.iconPadding * 2)
    .height(this.iconSize + this.iconPadding * 2)
    .backgroundColor(this.bgColor)
    .enabled(!this.disabled)
    .onClick(() => {
      if (this.onTap && !this.disabled) {
        this.onTap();
      }
    })
  }
}

/**
 * 主按钮组件
 */
@Component
export struct PrimaryButton {
  @Prop text: string;
  @Prop icon?: Resource;
  @Prop loading: boolean = false;
  @Prop disabled: boolean = false;
  @Prop fullWidth: boolean = false;
  onTap?: () => void;

  build() {
    Button({ type: ButtonType.Capsule }) {
      Row({ space: 8 }) {
        if (this.loading) {
          LoadingProgress()
            .width(16)
            .height(16)
            .color(Color.White)
        } else if (this.icon) {
          Image(this.icon)
            .width(16)
            .height(16)
            .fillColor(Color.White)
        }

        Text(this.text)
          .fontSize(14)
          .fontColor(Color.White)
          .fontWeight(FontWeight.Medium)
      }
      .padding({ left: 16, right: 16 })
    }
    .height(40)
    .width(this.fullWidth ? '100%' : undefined)
    .backgroundColor(this.disabled ? ColorResources.TEXT_SECONDARY : ColorResources.ACCENT)
    .enabled(!this.disabled && !this.loading)
    .onClick(() => {
      if (this.onTap && !this.disabled && !this.loading) {
        this.onTap();
      }
    })
  }
}

/**
 * 文本按钮组件
 */
@Component
export struct TextButton {
  @Prop text: string;
  @Prop color: ResourceColor = ColorResources.ACCENT;
  @Prop disabled: boolean = false;
  onTap?: () => void;

  build() {
    Text(this.text)
      .fontSize(14)
      .fontColor(this.disabled ? ColorResources.TEXT_SECONDARY : this.color)
      .fontWeight(FontWeight.Medium)
      .padding({ left: 8, right: 8, top: 4, bottom: 4 })
      .onClick(() => {
        if (this.onTap && !this.disabled) {
          this.onTap();
        }
      })
  }
}

/**
 * 卡片组件
 */
@Component
export struct Card {
  @Prop contentPadding: number = 16; // 重命名：padding -> contentPadding
  @Prop radius: number = 12;
  @Prop elevation: number = 0;
  @BuilderParam content: () => void;

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .padding(this.contentPadding)
    .backgroundColor(ColorResources.BG_SECONDARY)
    .borderRadius(this.radius)
    .shadow(this.elevation > 0 ? {
      radius: this.elevation * 2,
      color: 'rgba(0,0,0,0.1)',
      offsetY: this.elevation
    } : undefined)
  }
}

/**
 * 标签组件
 */
@Component
export struct Tag {
  @Prop text: string;
  @Prop color: ResourceColor = ColorResources.ACCENT;
  @Prop bgColor: ResourceColor = $r('app.color.text_color');

  build() {
    Text(this.text)
      .fontSize(12)
      .fontColor(this.color)
      .padding({ left: 8, right: 8, top: 2, bottom: 2 })
      .backgroundColor(this.bgColor)
      .borderRadius(4)
  }
}

/**
 * 头像组件
 */
@Component
export struct Avatar {
  @Prop icon: Resource;
  @Prop avatarSize: number = 40; // 重命名：size -> avatarSize
  @Prop bgColor: ResourceColor = ColorResources.BG_SECONDARY;

  build() {
    Column() {
      Image(this.icon)
        .width(this.avatarSize * 0.6)
        .height(this.avatarSize * 0.6)
        .fillColor(ColorResources.TEXT_PRIMARY)
    }
    .width(this.avatarSize)
    .height(this.avatarSize)
    .borderRadius(this.avatarSize / 2)
    .backgroundColor(this.bgColor)
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
  }
}

/**
 * 骨架屏组件
 */
@Component
export struct Skeleton {
  @Prop skeletonWidth: Length = '100%'; // 重命名：width -> skeletonWidth
  @Prop skeletonHeight: Length = 16;    // 重命名：height -> skeletonHeight
  @Prop radius: number = 4;

  build() {
    Column()
      .width(this.skeletonWidth)
      .height(this.skeletonHeight)
      .borderRadius(this.radius)
      .backgroundColor(ColorResources.BORDER_PRIMARY)
      .opacity(0.5)
  }
}

/**
 * 消息骨架屏组件
 */
@Component
export struct MessageSkeleton {
  @Prop isUser: boolean = false;

  build() {
    Row() {
      if (!this.isUser) {
        // 更新调用处的属性名以匹配 Skeleton 组件的新定义
        Skeleton({ skeletonWidth: 32, skeletonHeight: 32, radius: 16 })
          .margin({ right: 12 })
      }

      Column({ space: 8 }) {
        Skeleton({ skeletonWidth: '80%', skeletonHeight: 14 })
        Skeleton({ skeletonWidth: '60%', skeletonHeight: 14 })
        Skeleton({ skeletonWidth: '40%', skeletonHeight: 14 })
      }
      .layoutWeight(1)
      .alignItems(this.isUser ? HorizontalAlign.End : HorizontalAlign.Start)

      if (this.isUser) {
        // 更新调用处的属性名以匹配 Skeleton 组件的新定义
        Skeleton({ skeletonWidth: 32, skeletonHeight: 32, radius: 16 })
          .margin({ left: 12 })
      }
    }
    .width('100%')
    .padding(16)
  }
}