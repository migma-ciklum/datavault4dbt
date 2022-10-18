# datavault4dbt by [Scalefree International GmbH](https://www.scalefree.com)

<img src="https://user-images.githubusercontent.com/81677440/195860893-435b5faa-71f1-4e01-969d-3593a808daa8.png">


---
## Supported platforms:
Currently supported platforms are:
* Google Bigquery
* Exasol
* Snowflake

We are working continuously at high pressure to adapt the package for large variety of different platforms. In the future, the package will hopefully be available for SQL Server, Oracle and many more.

---


## Installation
Datavault4dbt is not yet listed on dbt Hub, but we are working hard to get it there. Until then, you can still experience datavault4dbt by installing via Git. Just add the following lines to your packages.yml: 

      packages:
        - git: "https://github.com/ScalefreeCOM/datavault4dbt.git"
          revision: 1.0.0

For further information on how to install packages in dbt, please visit the following link: 
[https://docs.getdbt.com/docs/building-a-dbt-project/package-management](https://docs.getdbt.com/docs/building-a-dbt-project/package-management#how-do-i-add-a-package-to-my-project)

### Global variables
datavault4dbt is highly customizable by using many global variables. Since they are applied on multiple levels, a high rate of standardization across your data vault 2.0 solution is guaranteed. The default values of those variables are set inside the packages `dbt_project.yml` and should be copied to your own `dbt_project.yml`. For an explanation of all global variables see [the wiki](https://github.com/ScalefreeCOM/datavault4dbt/wiki/Global-variables).

---
## Usage
The datavault4dbt package provides macros for Staging and Creation of all DataVault-Entities you need, to build your own DataVault2.0 solution. The usage of the macros is well-explained in the documentation: https://github.com/ScalefreeCOM/datavault4dbt/wiki

---
## Contributing
[View our contribution guidelines](CONTRIBUTING.md)

---
## License
[Apache 2.0](LICENSE.md)

[<img src="https://user-images.githubusercontent.com/81677440/195876189-7bb21215-26f1-428a-9a0f-5fb333a2747f.jpg" width=50% align=right>](https://www.scalefree.com)

## Contact
For questions, feedback, etc. reach out to us via datavault4dbt@scalefree.com!

