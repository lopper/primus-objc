# Uncomment the next line to define a global platform for your project
platform :ios, '11.0'

source 'git@bitbucket.org:funpokes/fppodspec.git'
source 'https://cdn.cocoapods.org/'


target 'Primus' do
  # Comment the next line if you don't want to use dynamic frameworks
  use_frameworks!
  pod 'Emitter', '~> 0.0.9'
  pod 'Reachability', '~> 3.2'
  pod 'GCDTimer', '~> 1.1.0'
  pod 'libextobjc/EXTScope', '~> 0.6'
  #pod 'socket.IO', '~> 0.5.2'
  pod 'FPSocketRocket', '~> 0.4.1.2'
  # Pods for Primus

  target 'PrimusTests' do
    inherit! :search_paths
    pod 'Specta' 
    pod 'Expecta'
    pod 'OCMockito'
    # Pods for testing
  end

end
