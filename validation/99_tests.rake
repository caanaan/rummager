task :test_img_build => [
    :"images:img_one:build",
    :"images:img_two:build",
]

task :test_img_rmi => [
    :"images:img_two:rmi",
    :"images:img_one:rmi",
]

task :test_all => [
    :test_img_build,
    :test_container_start,
    :test_container_stop,
    :test_container_rm,
    :test_img_rmi,
]