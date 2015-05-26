require 'rake'
require 'logger'
require 'rummager'

Rummager::ClickContainer.new 'container_one', {
    :image_name => 'img_one',
    :noclean => 'false',
}

Rummager::ClickContainer.new 'container_two', {
    :image_name => 'img_two',
    :volumes_from => ['container_one'],
}

Rummager::ClickContainer.new 'container_three', {
    :image_name => 'debian4yocto',
    :repo_base => 'y3ddet',
    :image_nobuild => true,
    :allow_enter => true,
}

Rummager::ClickCntnrExec.new 'exec_in_two', {
    :container_name => 'container_two',
    :exec_list => [
        Rummager.cmd_shexec("echo 'this is a test in container two'"),
    ],
}

Rummager::ClickCntnrExec.new 'exec_in_two_with_test_false', {
    :container_name => 'container_two',
    :needed_test => ["/bin/false"],
    :exec_list => [
        Rummager.cmd_shexec("echo 'this exec should not run as @needed_test is always false'"),
    ],
}

Rummager::ClickCntnrExec.new 'exec_in_two_with_test_true', {
    :container_name => 'container_two',
    :needed_test => ["/usr/bin/test","-e","/bin/sh"],
    :exec_list => [
        Rummager.cmd_shexec("echo 'this exec runs because @needed_test is always true'"),
    ],
}

Rummager::ClickCntnrExec.new 'exec_in_three', {
    :container_name => 'container_three',
    :exec_list => [
        Rummager.cmd_bashexec("echo 'this is a test in container three'"),
    ],
}

task :test_container_start => [
    :"containers:container_one:start",
    :"containers:container_two:start",
]

task :test_container_execution => [
    :"containers:container_two:jobs:exec_in_two",
    :"containers:container_two:jobs:exec_in_two_with_test_false",
    :"containers:container_two:jobs:exec_in_two_with_test_true",
    :"containers:container_three:jobs:exec_in_three",
]

task :test_container_stop => [
    :"containers:container_two:stop",
    :"containers:container_one:stop",
]

task :test_container_rm => [
    :"containers:container_three:rm",
    :"containers:container_two:rm",
    :"containers:container_one:rm",
]
