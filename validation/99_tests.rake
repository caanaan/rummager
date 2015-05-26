
task :test_all => [
    :test_image_build,
    :test_container_execution,
    :test_container_stop,
    :test_container_stop,
    :test_image_rmi,
]