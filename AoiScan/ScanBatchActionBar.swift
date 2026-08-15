//
//  ScanBatchActionBar.swift
//  AoiScan
//

import SwiftUI


struct ScanBatchActionBar:View {
    let selectedCount:Int
    let onShare:()->Void
    let onMerge:()->Void
    let onMove:()->Void
    let onDelete:()->Void

    var body:some View {
        HStack(spacing:12) {
            actionButton(
                title:L10n.text("分享"),
                systemImage:"square.and.arrow.up",
                tint:.blue,
                disabled:selectedCount == 0,
                action:onShare
            )

            actionButton(
                title:L10n.text("合并"),
                systemImage:"rectangle.stack.badge.plus",
                tint:.indigo,
                disabled:selectedCount < 2,
                action:onMerge
            )

            actionButton(
                title:L10n.text("移动"),
                systemImage:"folder",
                tint:.orange,
                disabled:selectedCount == 0,
                action:onMove
            )

            actionButton(
                title:L10n.text("删除"),
                systemImage:"trash",
                tint:.red,
                disabled:selectedCount == 0,
                action:onDelete
            )
        }
        .padding(.horizontal,20)
        .padding(.top,10)
        .padding(.bottom,24)
        .background(.bar)
        .overlay(alignment:.top) {
            Divider()
        }
    }

    private func actionButton(
        title:String,
        systemImage:String,
        tint:Color,
        disabled:Bool,
        action:@escaping ()->Void
    )->some View {
        Button(action:action) {
            VStack(spacing:5) {
                Image(systemName:systemImage)
                    .font(.system(size:20, weight:.semibold))

                Text(title)
                    .font(.caption)
            }
            .foregroundStyle(disabled ? Color.secondary : tint)
            .frame(maxWidth:.infinity)
            .frame(height:48)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(disabled)
        .accessibilityLabel(title)
    }
}
