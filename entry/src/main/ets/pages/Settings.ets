// 主设置页面

// 跳转页面入口函数
@Builder
export function SettingsBuilder() {
  Settings();
}

@Preview
@Component
struct Settings {
  // 控制跳转的对象
  pathStack: NavPathStack = new NavPathStack();

  build() {
    Navigation() {
      List({space:10}) {
        ListItemGroup() {
          ListItem({ style: ListItemStyle.CARD }) {
            CardItem() {}
          }
        }
      }

    }
    .title('设置')
  }
}

// import { GlobalInfoModel, StorageKey } from '@ohos/common';
// import { BreakpointType, BreakpointTypeEnum, CommonConstants, TopNavigationView } from '@ohos/common';
// import { AboutBindSheetEvent, MinePageVM } from '../viewmodel/MinePageVM';
// import { MinePageState } from '../viewmodel/MinePageState';
// import { CardItem } from '../component/CardItem';
//
// @Component
// export struct MineView {
//   viewModel: MinePageVM = MinePageVM.getInstance();
//   @State minePageState: MinePageState = this.viewModel.getState();
//   @StorageProp(StorageKey.GLOBAL_INFO) globalInfoModel: GlobalInfoModel = AppStorage.get(StorageKey.GLOBAL_INFO)!;
//
//   throttle(func: Function, interval: number) {
//     let lastTime = 0;
//     return () => {
//       const nowTime = Date.now();
//       const remainTime = interval - (nowTime - lastTime);
//       if (remainTime <= 0) {
//         lastTime = nowTime;
//         func();
//       }
//     };
//   }
//
//   build() {
//     Column() {
//       TopNavigationView({ topNavigationData: {
//         fontSize:new BreakpointType({
//           sm: $r('sys.float.Title_M'),
//           md: $r('sys.float.Title_L'),
//           lg: $r('sys.float.Title_L'),
//           xl: $r('sys.float.Title_S'),
//         }).getValue(this.globalInfoModel.currentBreakpoint),
//         bgColor:$r('sys.color.background_secondary'),
//         title: $r('app.string.mine_title'),
//         isFullScreen: true,
//       }});
//
//       List() {
//         ListItemGroup() {
//           ListItem({ style: ListItemStyle.CARD }) {
//             CardItem({
//               isShow: this.minePageState.aboutViewShow,
//               textContent: $r('app.string.about'),
//               symbolSrc: $r('sys.symbol.info_circle'),
//               onclick: () => {
//                 this.viewModel.sendEvent(new AboutBindSheetEvent(true));
//               },
//               onClose: () => {
//                 this.viewModel.sendEvent(new AboutBindSheetEvent(false));
//               },
//             })
//           }
//           .height(undefined)
//           .width(CommonConstants.FULL_PERCENT)
//         }
//         .divider({
//           strokeWidth: $r('app.float.mine_divider'),
//           color: $r('sys.color.comp_divider'),
//           startMargin: $r('sys.float.padding_level24'),
//           endMargin: $r('sys.float.padding_level6'),
//         })
//         .margin({ top: $r('sys.float.padding_level6') })
//         .padding($r('sys.float.padding_level2'))
//         .backgroundColor($r('sys.color.comp_background_primary'))
//         .borderRadius($r('sys.float.corner_radius_level8'))
//       }
//       .edgeEffect(EdgeEffect.Spring, { alwaysEnabled: true })
//       .width(CommonConstants.FULL_PERCENT)
//       .height(CommonConstants.FULL_PERCENT)
//       .padding(new BreakpointType<Padding>({
//         sm: {
//           left: $r('sys.float.padding_level8'),
//           right: $r('sys.float.padding_level8')
//         },
//         md: {
//           left: $r('sys.float.padding_level12'),
//           right: $r('sys.float.padding_level12')
//         },
//         lg: {
//           left: $r('sys.float.padding_level16'),
//           right: $r('sys.float.padding_level16')
//         },
//       }).getValue(this.globalInfoModel.currentBreakpoint))
//       .backgroundColor($r('sys.color.background_secondary'))
//     }
//     .width(CommonConstants.FULL_PERCENT)
//     .height(CommonConstants.FULL_PERCENT)
//     .padding({
//       left: this.globalInfoModel.currentBreakpoint === BreakpointTypeEnum.LG ? CommonConstants.TAB_BAR_WIDTH : 0,
//     })
//   }
// }