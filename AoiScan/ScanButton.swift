//
//  ScanButton.swift
//  AoiScan
//

import SwiftUI


struct ScanButton: View {
    
    
    @State private var rotateGradient = false
    
    
    var action: () -> Void
    
    
    var body: some View {
        
        
        Button {
            
            action()
            
        } label: {
            
            
            ZStack {
                
                
                // 动态彩色光环
                Circle()
                    .stroke(
                        AngularGradient(
                            colors: [
                                .blue,
                                .cyan,
                                .green,
                                .yellow,
                                .orange,
                                .pink,
                                .purple,
                                .blue
                            ],
                            center: .center,
                            angle: .degrees(
                                rotateGradient ? 360 : 0
                            )
                        ),
                        lineWidth: 3
                    )
                    .frame(
                        width: 94,
                        height: 94
                    )
                
                
                
                // 黑色按钮
                Circle()
                    .fill(Color.black)
                    .frame(
                        width: 82,
                        height: 82
                    )
                
                
                
                // 相机图标
                Image(systemName: "camera")
                    .font(
                        .system(
                            size: 32,
                            weight: .light
                        )
                    )
                    .foregroundColor(.white)
                
                
            }
            
        }
        .buttonStyle(.plain)
        .accessibilityLabel("扫描")
        .onAppear {
            
            withAnimation(
                .linear(duration: 4)
                .repeatForever(
                    autoreverses: false
                )
            ) {
                
                rotateGradient = true
                
            }
        }
        
    }
}



#Preview {
    
    ScanButton {
        print("扫描")
    }
    
}


