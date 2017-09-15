#-- copyright
# OpenProject is a project management system.
# Copyright (C) 2012-2017 the OpenProject Foundation (OPF)
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License version 3.
#
# OpenProject is a fork of ChiliProject, which is a fork of Redmine. The copyright follows:
# Copyright (C) 2006-2017 Jean-Philippe Lang
# Copyright (C) 2010-2013 the ChiliProject Team
#
# This program is free software; you can redistribute it and/or
# modify it under the terms of the GNU General Public License
# as published by the Free Software Foundation; either version 2
# of the License, or (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA  02110-1301, USA.
#
# See doc/COPYRIGHT.rdoc for more details.
#++

class GenerateWpClosure < ActiveRecord::Migration[5.0]
  def up
    change_table :relations do |r|
      relation_types.each do |column|
        r.column column, :integer, default: 0
        r.index column
      end
    end

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE
        relations
      SET
        relates =    CASE
                     WHEN relations.relation_type = 'relates'
                     THEN 1
                     ELSE 0
                     END,
        duplicates = CASE
                     WHEN relations.relation_type = 'duplicates'
                     THEN 1
                     ELSE 0
                     END,
        blocks =     CASE
                     WHEN relations.relation_type = 'blocks'
                     THEN 1
                     ELSE 0
                     END,
        follows =    CASE
                     WHEN relations.relation_type = 'precedes'
                     THEN 1
                     ELSE 0
                     END,
        includes =   CASE
                     WHEN relations.relation_type = 'includes'
                     THEN 1
                     ELSE 0
                     END,
        requires =   CASE
                     WHEN relations.relation_type = 'requires'
                     THEN 1
                     ELSE 0
                     END
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE
        relations
      SET
        from_id = to_id,
        to_id = from_id
      WHERE
        relation_type = 'precedes'
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      INSERT INTO relations
        (from_id, to_id, hierarchy)
      SELECT w1.id, w2.id, 1
      FROM work_packages w1
      JOIN work_packages w2
      ON w1.id = w2.parent_id
    SQL

    WorkPackage.rebuild_dag!

    relation_types.each do |column|
      change_column_null :relations, column, true
    end

    remove_column :relations, :relation_type
  end

  def down
    ActiveRecord::Base.connection.execute <<-SQL
      DELETE FROM relations
      WHERE hierarchy > 0
      OR #{relation_types.join(' + ')} > 1
    SQL

    ActiveRecord::Base.connection.execute <<-SQL
      UPDATE
        relations
      SET
        from_id = to_id,
        to_id = from_id
      WHERE
        follows = 1
    SQL

    relation_types.each do |column|
      remove_column :relations, column
    end

    add_column :relations, :relation_type, :string

    #ActiveRecord::Base.connection.execute <<-SQL
    #  DELETE FROM relations
    #  WHERE relation_type = 'hierarchy'
    #SQL
  end

  def relation_types
    %i(hierarchy relates duplicates blocks follows includes requires)
  end

  def exactly_one_column_eql_1(columns, prefix = '')
    columns.map { |column| "#{prefix}#{column} = 1" }.join(' XOR ')
  end

  def sum_of_columns(columns, prefix = '')
    columns.map { |column| "#{prefix}#{column}" }.join(' + ')
  end
end
