
_ = require 'lodash'

db_obj = require '../examples/create_table/output.json'

db_obj = _.compact _.reject db_obj, (val)->
  return val == ';'

#console.log db_obj

out = []

out.push """
  import { Model, many, fk, Schema } from 'redux-orm';
"""

_.each db_obj, (table_obj)->

  propTypes = _.compact _.map table_obj.fields, (field_obj)->
    type = switch field_obj.type
      when 'varchar','char','text','tinytext','mediumtext','longtext' then 'string'
      when 'datetime','date' then 'string'
      when 'float','decimal','double','int','tinyint','bigint','timestamp' then 'number'
      when 'enum' then "oneOf(#{JSON.stringify(field_obj.values)})"
      else throw new Error("Unknown field_obj.type '#{field_obj.type}'")

    return """
      #{field_obj.name}: React.PropTypes.#{type}#{if (!field_obj.allowNull) then '.isRequired' else ''}
    """

  defaults = {}
  _.each table_obj.fields, (field_obj)->
    if field_obj.default
      defaults[field_obj.name] = field_obj.default
    return

  constraints = _.compact _.map table_obj.constraint, (constraint_obj)->
    if constraint_obj.keys.length < 1
      return ""

    return """
      #{constraint_obj.keys[0]}: fk('#{constraint_obj.refTable.tableName}')
    """

  backend = {}

  if table_obj.pk && table_obj.pk.length > 0
    backend.idAttribute = "'#{table_obj.pk[0]}'"


  out.push """
    export class #{table_obj.tableName} extends Model {}
    #{table_obj.tableName}.modelName = '#{table_obj.tableName}';
    #{table_obj.tableName}.backend = #{JSON.stringify(backend)};
    #{table_obj.tableName}.fields = {
      #{constraints.join ',\n  '}
    };
    #{table_obj.tableName}.PropTypes = {
      #{propTypes.join ',\n  '}
    };
    #{table_obj.tableName}.defaultProps = #{JSON.stringify(defaults)};
  """
  return



full_out = out.join '\n'

console.log full_out


