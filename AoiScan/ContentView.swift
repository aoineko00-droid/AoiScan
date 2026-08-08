import SwiftUI

struct ContentView: View {
    
    @State private var rotateGradient = false
    
    // 控制扫描页面显示
    @State private var showScanner = false
    
    
    var body: some View {
        
        ZStack {
            
            Color.white
                .ignoresSafeArea()
            
            
            VStack {
                
                Spacer()
                
                
                Button {
                    
                    showScanner = true
                    
                } label: {
                    
                    ZStack {
                        
                        // 动态彩色边框
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
                                    center: .center
                                ),
                                lineWidth: 3
                            )
                            .frame(
                                width: 94,
                                height: 94
                            )
                            .rotationEffect(
                                .degrees(
                                    rotateGradient ? 360 : 0
                                )
                            )
                            .animation(
                                .linear(duration: 4)
                                .repeatForever(
                                    autoreverses: false
                                ),
                                value: rotateGradient
                            )
                        
                        
                        // 黑色圆形按钮
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
                .padding(.bottom, 50)
                
            }
            
        }
        .onAppear {
            rotateGradient = true
        }
        
        // 打开苹果扫描器
        .sheet(isPresented: $showScanner) {
            DocumentScanner()
        }
        
    }
}


#Preview {
    ContentView()
}
