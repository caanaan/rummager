module Rummager

    def Rummager.cmd_bashexec(cmdstring)
        {
            :cmd=> [ "/bin/bash","-c", cmdstring ],
        }
    end # cmd_bashexec

    def Rummager.cmd_gitmirror(filepath,giturl)
        {
            :cmd=> [ "/bin/bash","-c",
                "if [[ -d #{filepath} ]]; then\n"                       \
                "  /usr/bin/git --git-dir=#{filepath} fetch --all\n"    \
                "else\n"                                                \
                "  /usr/bin/git clone --mirror #{giturl} #{filepath}\n" \
                "fi\n"
            ],
        }
    end # cmd_gitmirror

    def Rummager.cmd_gitupdate(filepath)
        {
            :cmd=> [ "/bin/bash","-c",
                "/usr/bin/git --git-dir=#{filepath} fetch --all",
            ],
        }
    end # cmd_gitupdate

    def Rummager.cmd_gitclone(branch,srcpath,clonepath)
        {
            :cmd => ["/bin/bash","-c",
                "/usr/bin/git clone --branch #{branch} #{srcpath} #{clonepath}"
            ],
        }
    end # cmd_gitclone

    def Rummager.cmd_gitcheckout(commithash,srcpath,clonepath)
        {
            :cmd => ["/bin/bash","-c",
                "/usr/bin/git clone --no-checkout #{srcpath} #{clonepath} &&"  \
                "/usr/bin/git --work-tree #{clonepath} --git-dir #{clonepath}/.git checkout #{commithash}\n"
            ],
        }
    end # cmd_gitcheckout

end # Rummager